{{
    config(
        materialized="incremental",
        unique_key=['date_day', 'visitor_id'],
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

-- Intermediate table for subscription acquisition visitor counts
-- Pre-computes unique visitor-day combinations from page.display events
-- This table is used by all daily/weekly/monthly aggregation models to avoid
-- redundant expensive DISTINCT operations on the event-level table

SELECT DISTINCT
    visit_time::DATE AS date_day,
    visitor_id
FROM {{ ref('stg_piano_events__page_views') }}
WHERE 1=1
{% if is_incremental() %}
    AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date_day) FROM {{ this }}))
{% endif %}
