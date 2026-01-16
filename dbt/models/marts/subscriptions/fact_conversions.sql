{{ config(materialized="table") }}

WITH web_conversions AS (

    SELECT *
    FROM {{ ref('int_piano__conversion_attribution_web') }}

),

app_conversions AS (

    SELECT *
    FROM {{ ref('int_piano__conversion_attribution_app') }}

)

SELECT * FROM web_conversions

UNION ALL

SELECT * FROM app_conversions
