{{ config(
    materialized="table",
    tags=["mart","core",'dim']
    )
}}

WITH mapping AS (

    SELECT *
    FROM {{ ref('geo_mapping') }}

    UNION ALL

    SELECT 'Unknown' AS geo_country, 'Unknown' AS geo_region

),

surrogate_key AS (
    SELECT
        {{ generate_geo_id('geo_country', 'geo_region') }} AS geo_id,
        geo_country,
        geo_region
    FROM mapping
)

SELECT *
FROM surrogate_key
