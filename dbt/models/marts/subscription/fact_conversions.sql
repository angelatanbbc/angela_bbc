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

),

attribution AS (

    SELECT
        subscription_id,
        attribution_source,
        position_weight
    FROM {{ ref('subscription_attribution_model') }}

)

SELECT
    c.*,
    IFNULL(IFF(a.attribution_source != 'Paid', 'Organic', a.attribution_source), 'Organic') AS attribution_source,
    a.attribution_source AS attribution_source_detail,
    IFNULL(a.position_weight, 1) AS position_weight
FROM unioned c
LEFT JOIN attribution a USING (subscription_id)
