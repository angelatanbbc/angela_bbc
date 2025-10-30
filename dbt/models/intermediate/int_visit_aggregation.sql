{{ config(materialized="view") }}

{%- set event_columns = [
    'visit_id',
    'visit_time',
    'visitor_id',
    'user_id',
    'event_time',
    'device_type',
    'src',
    'src_detail'
] -%}

WITH all_events AS (

    SELECT
        {{ event_columns | join(',\n') }}
    FROM {{ ref('stg_piano_events__page_views') }}

    UNION ALL

    SELECT
        {{ event_columns | join(',\n') }}
    FROM {{ ref('stg_piano_events__exposures') }}

    UNION ALL

    SELECT
        {{ event_columns | join(',\n') }}
    FROM {{ ref('stg_piano_events__conversions') }}

),

aggregated_visits AS (
    
    SELECT
        visit_id,
        visit_time,
        visitor_id,
        user_id,
        device_type,
        src,
        src_detail,
        MIN(event_time) AS first_event_time,
        MAX(event_time) AS last_event_time
    FROM all_events
    GROUP BY ALL

)

SELECT *
FROM aggregated_visits
