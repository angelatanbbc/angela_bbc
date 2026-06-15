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

latest AS (

    SELECT
        template_id,
        template_name
    FROM base
    QUALIFY ROW_NUMBER() OVER (PARTITION BY template_id ORDER BY event_time DESC) = 1

)

SELECT
    template_id,
    template_name,
    CASE
        WHEN template_name ILIKE '%gate%' THEN 'Paywall'
        WHEN template_name ILIKE '%ribbon%' THEN 'Ribbon'
        WHEN template_name ILIKE '%landing%page%' THEN 'Subscription Landing Page'
        ELSE 'Other'
    END AS template_type
FROM latest
ORDER BY template_id
