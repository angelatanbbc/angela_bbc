{{ config(materialized="view") }}

WITH web_exposures AS (

    SELECT *
    FROM {{ ref('int_piano__exposures_web') }}

)

SELECT * FROM web_exposures
