{{
    config(
        materialized="incremental",
        unique_key="pageview_id",
        incremental_strategy="merge",
        on_schema_change="sync_all_columns",
        tags=["piano", "intermediate"]
    )
}}

-- Aggregates page.scroll events to the pageview grain. Piano stores scroll depth
-- as a 0-1 fraction on page.scroll events only (never on page.display);
-- converted here to a 0-100 percentage.

SELECT
    pageview_id,
    MAX(event_time) AS last_event_time,
    ROUND(MAX(scroll_depth) * 100, 1) AS scroll_depth_pct
FROM {{ ref('int_piano__events_cleaned') }}
WHERE
    event_name = 'page.scroll'
    AND pageview_id IS NOT NULL
    AND scroll_depth IS NOT NULL
    {{ piano_page_view_event_window() }}
GROUP BY pageview_id
