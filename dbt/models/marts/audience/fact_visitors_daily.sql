{{
    config(
        materialized="incremental",
        unique_key=['geo_country', 'device_type', 'app_type', 'os_group', 'date_day', 'visitor_id'],
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

-- Intermediate table for subscription acquisition visitor counts
-- Pre-computes unique visitor-day combinations from page.display events
-- This table is used by all daily/weekly/monthly aggregation models to avoid
-- redundant expensive DISTINCT operations on the event-level table


WITH visitors AS (

    SELECT
        pageview_time::DATE AS date_day,
        geo_country,
        device_type,
        app_type,
        os_group,
        visitor_id,
        COUNT(DISTINCT visit_id) AS n_visits
    FROM {{ ref('fact_page_views') }}
    {% if is_incremental() %}
        WHERE pageview_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date_day) FROM {{ this }}))
    {% endif %}
    GROUP BY ALL

)

SELECT *
FROM visitors
