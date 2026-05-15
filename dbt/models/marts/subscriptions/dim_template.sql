{{ config(materialized="table") }}

WITH base AS (

    SELECT
        template_id,
        template_name,
        event_time
    FROM {{ ref('stg_piano__composer_events') }}
    WHERE
        template_id IS NOT NULL
        AND template_name IS NOT NULL

),

name_spans AS (

    SELECT
        template_id,
        template_name,
        MIN(event_time) AS first_seen,
        MAX(event_time) AS last_seen
    FROM base
    GROUP BY ALL

),

ranked AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY template_id
            ORDER BY first_seen
        ) AS name_version_number,
        COUNT(*) OVER (PARTITION BY template_id) AS total_name_versions
    FROM name_spans

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['template_id', 'name_version_number']) }} AS template_version_key,
    template_id,
    template_name,
    CASE
        WHEN template_name ILIKE '%gate%' THEN 'Paywall'
        WHEN template_name ILIKE '%ribbon%' THEN 'Ribbon'
        WHEN template_name ILIKE '%landing%page%' THEN 'Subscription Landing Page'
        ELSE 'Other'
    END AS template_type,
    name_version_number,
    total_name_versions,
    first_seen AS valid_from,
    LEAD(first_seen) OVER (PARTITION BY template_id ORDER BY first_seen) AS valid_until,
    IFF(name_version_number = total_name_versions, TRUE, FALSE) AS is_current
FROM ranked
ORDER BY template_id, valid_from
