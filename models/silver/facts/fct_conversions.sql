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

-- The share of each conversion's position-based credit that went to paid touches (0 to 1).
-- Touch-level credit stays in fct_attribution_touchpoints.
attribution AS (

    SELECT
        conversion_id,
        SUM(IFF(is_paid_touch, position_weight, 0)) AS paid_attribution_weight
    FROM {{ ref('fct_attribution_touchpoints') }}
    GROUP BY conversion_id

),

terms AS (

    SELECT
        term_id,
        subscription_weight
    FROM {{ ref('dim_term') }}

)

SELECT
    c.*,
    -- app conversions and web conversions the attribution does not cover count as organic, as before
    COALESCE(a.paid_attribution_weight, 0)::NUMBER(18, 6) AS paid_attribution_weight,
    COALESCE(t.subscription_weight, 1) AS subscription_weight
FROM unioned c
LEFT JOIN attribution a
    ON c.conversion_id = a.conversion_id
LEFT JOIN terms t
    ON c.term_id = t.term_id
