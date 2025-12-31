{{ config(materialized="table") }}

WITH exposures AS (

    SELECT *
    FROM {{ ref('fact_exposures') }}

)

SELECT DISTINCT
    template_id,
    template_name,
    CASE
        WHEN template_name ILIKE '%gate%' THEN 'Paywall'
        WHEN template_name ILIKE '%ribbon%' THEN 'Ribbon'
        WHEN template_name ILIKE '%landing page%' THEN 'Subscription Landing Page'
        ELSE 'Other'
    END AS template_type
FROM exposures
WHERE
    template_id IS NOT NULL
