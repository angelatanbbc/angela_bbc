{{ config(materialized='table') }}

WITH mapping AS (

    SELECT *
    FROM {{ ref('geo_mapping') }}

),

surrogate_key AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['geo_country', 'geo_region']) }} AS geo_id,
        geo_country,
        geo_region
    FROM mapping
)

SELECT *
FROM surrogate_key
