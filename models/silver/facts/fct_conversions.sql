{{
    config(
        materialized="table",
        tags=['fct', 'subscriptions']
    )
}}

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
    FROM {{ ref('fct_subscription_attribution') }}

),

terms AS (

    SELECT
        term_id,
        subscription_weight
    FROM {{ ref('dim_term') }}

)

SELECT
    c.*,
    COALESCE(IFF(a.attribution_source != 'Paid', 'Organic', a.attribution_source), 'Organic') AS attribution_source,
    a.attribution_source AS attribution_source_detail,
    COALESCE(a.position_weight, 1) AS position_weight,
    COALESCE(t.subscription_weight, 1) AS subscription_weight
FROM unioned c
LEFT JOIN attribution a USING (subscription_id)
LEFT JOIN terms t
    ON c.term_id = t.term_id
