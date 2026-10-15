{{
    config(
        materialized="incremental",
        unique_key="pageview_id",
        incremental_strategy="merge",
        on_schema_change="sync_all_columns",
        tags=["piano", "intermediate"]
    )
}}

-- Aggregates all ad impression event families to the pageview grain.
-- ad.impression is the only event that carries ad_revenue (Piano Ad Revenue
-- Insights); the other families are impression counts only.

SELECT
    pageview_id,
    MAX(event_time) AS last_event_time,
    COUNT(*) AS ad_impression_count,
    SUM(COALESCE(ad_revenue, 0)) AS total_ad_revenue,
    COUNT_IF(event_name = 'ad.impression') AS monetized_impression_count,
    COUNT_IF(event_name = 'publisher.display') AS publisher_impression_count,
    COUNT_IF(event_name = 'widget.impression') AS widget_impression_count
FROM {{ ref('int_piano__events_cleaned') }}
WHERE
    event_name IN ('ad.impression', 'publisher.display', 'widget.impression')
    AND pageview_id IS NOT NULL
    {{ piano_page_view_event_window() }}
GROUP BY pageview_id
