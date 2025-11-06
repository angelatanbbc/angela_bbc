{{ config(materialized="table") }}

WITH conversions AS (

    SELECT
        c.conversion_time::DATE AS event_date,
        'New Subscription' AS event_type,
        c.subscription_id,
        c.conversion_time AS event_time,
        c.term_id,
        t.billing_period,
        t.price AS transaction_value,
        t.amortised_price AS mrr_change_amount,
        1 AS subscription_period_number
    FROM {{ ref('fact_conversions') }} c
    LEFT JOIN {{ ref('dim_term') }} t
        ON c.term_id = t.term_id

),

subs_actions AS (

    SELECT
        a.event_time::DATE AS event_date,
        a.subscription_action AS event_type,
        a.subscription_id,
        a.event_time,
        a.term[0]['term_id2']::STRING AS term_id,
        t.billing_period,
        IFF(a.subscription_action = 'Renewed', t.price, 0) AS transaction_value,
        CASE a.subscription_action
            WHEN 'Renewed' THEN 0
            WHEN 'Canceled' THEN -t.amortised_price
            WHEN 'Expired' THEN -t.amortised_price
            WHEN 'Renewal failed, will not retry' THEN -t.amortised_price
            ELSE 0
        END AS mrr_change_amount,
        a.subscription_period_number
    FROM {{ ref('stg_piano_events__subscription_actions') }} a
    LEFT JOIN {{ ref('dim_term') }} t
        ON a.term[0]['term_id2']::STRING = t.term_id

),

unioned AS (

    SELECT *
    FROM conversions

    UNION ALL

    SELECT *
    FROM subs_actions

),

geo AS (

    SELECT
        u.*,
        c.geo_id
    FROM unioned u
    LEFT JOIN {{ ref('fact_conversions') }} c
        ON u.subscription_id = c.subscription_id

)


SELECT *
FROM geo
ORDER BY subscription_id, event_time
