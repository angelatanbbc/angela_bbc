{{
    config(
        materialized="incremental",
        unique_key=['subscription_action_id'],
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

WITH conversions AS (

    SELECT
        c.conversion_time::DATE AS event_date,
        'New Subscription' AS event_type,
        c.subscription_id,
        c.conversion_time AS event_time,
        c.term_id,
        t.billing_period,
        c.cart_turnovertaxfree AS transaction_value,
        1 AS subscription_period_number
    FROM {{ ref('fact_conversions') }} c
    LEFT JOIN {{ ref('dim_term') }} t
        ON c.term_id = t.term_id
    WHERE 1=1
    {% if is_incremental() %}
        AND c.conversion_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(event_date) FROM {{ this }}))
    {% endif %}

),

subs_actions AS (

    SELECT
        a.event_time::DATE AS event_date,
        a.subscription_action AS event_type,
        a.subscription_id,
        a.event_time,
        a.term[0]['term_id2']::STRING AS term_id,
        t.billing_period,
        a.cart_turnovertaxfree AS transaction_value,
        a.subscription_period_number
    FROM {{ ref('stg_piano_events__subscription_actions') }} a
    LEFT JOIN {{ ref('dim_term') }} t
        ON a.term[0]['term_id2']::STRING = t.term_id
    WHERE 1=1
    {% if is_incremental() %}
        AND a.event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(event_date) FROM {{ this }}))
    {% endif %}

),

unioned AS (

    SELECT *
    FROM conversions

    UNION ALL

    SELECT *
    FROM subs_actions

),

mrr AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['subscription_id', 'event_time', 'event_type'], 'subscription_action_id') }},
        *,
        LAG(transaction_value) IGNORE NULLS OVER (
            PARTITION BY subscription_id
            ORDER BY event_time
        ) AS previous_transaction_value,
        IFF(billing_period ILIKE '%year%', previous_transaction_value / 12, previous_transaction_value) AS previous_mrr,

        CASE event_type
            WHEN 'New Subscription' THEN IFF(billing_period ILIKE '%year%', transaction_value / 12, transaction_value)
            WHEN 'Renewed' THEN 0
            WHEN 'Canceled' THEN -previous_mrr
            WHEN 'Expired' THEN -previous_mrr
            WHEN 'Renewal failed, will not retry' THEN -previous_mrr
            ELSE 0
        END AS mrr_change_amount
    FROM unioned

),

geo AS (

    SELECT
        m.*,
        c.geo_id
    FROM mrr m
    LEFT JOIN {{ ref('fact_conversions') }} c
        ON m.subscription_id = c.subscription_id

)


SELECT *
FROM geo
ORDER BY subscription_id, event_time
