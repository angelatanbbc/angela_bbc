{{
    config(
        materialized="incremental",
        unique_key="pageview_id",
        incremental_strategy="merge",
        on_schema_change="sync_all_columns",
        tags=["piano", "intermediate"]
    )
}}

/*
Aggregates event_duration (milliseconds) to the pageview grain, feeding Piano's
time-based metrics (Time Spent, Time Spent / Visit, Time Spent / Visitor).

Reads from staging rather than int_piano__events_cleaned on purpose: Piano sums
event_duration across ALL event families, while the cleaned model keeps only the
families used for page view and subscription analysis. exclusion.* events are
Piano's own reporting exclusions and are dropped, as in the cleaned model.

Note: Piano's Time Spent / Visit filters on visit_duration > 0 (rounded to
seconds) while Time Spent / Visitor filters on event_duration > 0 (milliseconds),
so the two denominators classify materially different volumes of visits/visitors
as "having duration". Both raw ingredients are carried into fct_page_views so
each metric can apply its own filter.
*/

SELECT
    pageview_id,
    MAX(event_time) AS last_event_time,
    SUM(COALESCE(event_duration, 0)) AS event_duration_ms,
    COUNT_IF(event_duration > 0) AS events_with_duration_count
FROM {{ ref('stg_piano__studios_events') }}
WHERE
    pageview_id IS NOT NULL
    AND event_name NOT LIKE 'exclusion.%'
    {{ piano_page_view_event_window() }}
GROUP BY pageview_id
