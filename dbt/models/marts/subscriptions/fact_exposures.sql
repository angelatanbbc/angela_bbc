{{ config(materialized="table") }}

WITH web_exposures AS (

    SELECT *
    FROM {{ ref('int_piano__exposures_web') }}

),

app_exposures AS (

    SELECT *
    FROM {{ ref('int_piano__exposures_app') }}

)

SELECT * FROM web_exposures

UNION ALL

SELECT * FROM app_exposures
