{{ config(
    materialized="table",
    tags=['subscriptions', 'piano', 'mart', 'dim']
) }}

WITH composer_events AS (

    SELECT
        experience_id,
        experience_name,
        event_time
    FROM {{ ref('stg_piano__composer_events') }}
    WHERE
        event_name IN (
            'experience.action',
            'experience.interaction',
            'vx.conversion',
            'vx.conversion.optout'
        )
        AND experience_id IS NOT NULL
        AND experience_name IS NOT NULL

),

name_spans AS (

    SELECT
        experience_id,
        experience_name,
        MIN(event_time) AS first_seen
    FROM composer_events
    WHERE experience_name IS NOT NULL
    GROUP BY ALL

)

SELECT
    n.experience_id,
    n.experience_name,
    COALESCE(
        CASE
            WHEN n.experience_name ILIKE '%_web_%' THEN MD5('Web')
            WHEN n.experience_name ILIKE '%_app_%' THEN MD5('Mobile App')
            ELSE NULL
        END,
        MD5(s.app_type)) AS app_type_id
FROM name_spans n
LEFT JOIN {{ ref('experience_app_type') }} s
    ON n.experience_id = s.experience_id
QUALIFY ROW_NUMBER() OVER (PARTITION BY n.experience_id ORDER BY first_seen DESC) = 1
