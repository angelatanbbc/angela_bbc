{{
    config(
        materialized="table",
        tags=["mart","core",'dim']
    )
}}

/*
Every country and region combination the facts carry a geo_id for, so that every fact geo_id
resolves here. The geo_mapping seed lists the US and Canada regions; the facts add the rest of
the world (exposures and page views are global). Labels are normalised the same way as
generate_geo_id, so each geo_id has exactly one row.
*/

WITH observed_geographies AS (

    SELECT geo_country, geo_region
    FROM {{ ref('geo_mapping') }}

    UNION ALL

    SELECT 'Unknown' AS geo_country, 'Unknown' AS geo_region

    UNION ALL

    SELECT DISTINCT geo_country, geo_region
    FROM {{ ref('fct_exposures') }}

    UNION ALL

    SELECT DISTINCT geo_country, geo_region
    FROM {{ ref('fct_conversions') }}

    UNION ALL

    SELECT DISTINCT geo_country, geo_region
    FROM {{ ref('fct_subscription_events') }}

    UNION ALL

    SELECT DISTINCT geo_country, geo_region
    FROM {{ ref('int_piano__page_views') }}

),

normalised AS (

    SELECT DISTINCT
        COALESCE(NULLIF(geo_country, 'Unknown'), 'Unknown') AS geo_country,
        COALESCE(NULLIF(geo_region, 'Unknown'), 'Unknown') AS geo_region
    FROM observed_geographies

)

SELECT
    {{ generate_geo_id('geo_country', 'geo_region') }} AS geo_id,
    geo_country,
    geo_region
FROM normalised
