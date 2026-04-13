{{ config(materialized="table") }}

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
        MIN(event_time) AS first_seen,
        MAX(event_time) AS last_seen
    FROM composer_events
    WHERE experience_name IS NOT NULL
    GROUP BY ALL

),

ranked AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY experience_id
            ORDER BY first_seen
        ) AS name_version_number,
        COUNT(*) OVER (PARTITION BY experience_id) AS total_name_versions
    FROM name_spans

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['r.experience_id', 'r.name_version_number']) }} AS experience_version_key,
    r.experience_id,
    r.experience_name,
    s.app_type,
    r.name_version_number,
    r.total_name_versions,
    r.first_seen AS valid_from,
    LEAD(r.first_seen) OVER (PARTITION BY r.experience_id ORDER BY r.first_seen) AS valid_until,
    IFF(r.name_version_number = r.total_name_versions, TRUE, FALSE) AS is_current
FROM ranked r
LEFT JOIN {{ ref('experience_app_type') }} s
    ON r.experience_id = s.experience_id
ORDER BY r.experience_id, valid_from
