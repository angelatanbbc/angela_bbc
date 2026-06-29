{{
    config(
        materialized="incremental",
        unique_key='visitor_date_key',
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
        event_time::DATE AS date_key,
        app_type_id,
        device_type_id,
        os_group_id,
        geo_id,
        visitor_id,
        COUNT(DISTINCT visit_id) AS n_visits,
        COUNT(*) AS n_pageviews
    FROM {{ ref('stg_piano__analytics_events') }}
    WHERE 1=1
        AND geo_country IN ('United states', 'Canada')
    {% if is_incremental() %}
        AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date_key) FROM {{ this }}))
    {% endif %}
    GROUP BY ALL

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['geo_id', 'device_type_id', 'app_type_id', 'os_group_id', 'date_key', 'visitor_id']) }} AS visitor_date_key,
    *
FROM visitors
