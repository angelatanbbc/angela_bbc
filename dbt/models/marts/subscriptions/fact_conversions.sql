{{ config(materialized="table") }}

WITH web_conversions AS (

    SELECT *
    FROM {{ ref('int_piano__conversion_attribution_web') }}

),

app_conversions AS (

    SELECT *
    FROM {{ ref('int_piano__conversion_attribution_app') }}

),

unioned AS (

    SELECT * FROM web_conversions

    UNION ALL

    SELECT * FROM app_conversions

)

SELECT *
FROM unioned
QUALIFY ROW_NUMBER() OVER (PARTITION BY conversion_id ORDER BY conversion_time DESC) = 1
