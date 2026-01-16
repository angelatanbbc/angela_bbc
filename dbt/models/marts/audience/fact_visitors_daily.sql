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


WITH web_visitors AS (

    SELECT DISTINCT
        geo_country,
        app_type,
        visit_time::DATE AS date_day,
        visitor_id
    FROM {{ ref('stg_piano__subs_events_web') }}
    WHERE event_name = 'page.display'
    {% if is_incremental() %}
        AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date_day) FROM {{ this }}))
    {% endif %}

),

app_visitors AS (

    SELECT DISTINCT
        geo_country,
        app_type,
        visit_time::DATE AS date_day,
        visitor_id
    FROM {{ ref('stg_piano__subs_events_app') }}
    WHERE event_name = 'page.display'
    {% if is_incremental() %}
        AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date_day) FROM {{ this }}))
    {% endif %}

)

SELECT *
FROM web_visitors

UNION ALL

SELECT *
FROM app_visitors
