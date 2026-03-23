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


WITH web_visitors AS (

    SELECT
        pageview_time::DATE AS date_day,
        geo_country,
        device_type,
        app_type,
        os_group,
        visitor_id,
        COUNT(DISTINCT visit_id) AS n_visits
    FROM {{ ref('fact_page_views') }}
    WHERE app_type = 'Web'
    {% if is_incremental() %}
        AND pageview_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date_day) FROM {{ this }}))
    {% endif %}
    GROUP BY ALL

),

-- TODO: When we can bring app events to pageview fact table then we migrate this logic
app_visitors AS (

    SELECT
        visit_time::DATE AS date_day,
        geo_country,
        device_type,
        app_type,
        os_group,
        visitor_id,
        COUNT(DISTINCT visit_id) AS n_visits
    FROM {{ ref('int_piano__app_events') }}
    WHERE event_name = 'page.display'
    {% if is_incremental() %}
        AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date_day) FROM {{ this }}))
    {% endif %}
    GROUP BY ALL

)

SELECT *
FROM web_visitors

UNION ALL

SELECT *
FROM app_visitors
