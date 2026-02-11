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
        conversion_time AS event_time,
        'New Subscription' AS event_type,
        user_id,
        subscription_id,
        device_type AS conversion_device_type,
        app_type AS conversion_app_type,
        os_group AS conversion_os_group,
        term_id,
        term_name,
        billing_period,
        cart_turnovertaxfree AS transaction_value,
        subscription_period_number,
        geo_id,
        geo_country,
        geo_region,
        geo_city,
        cohort_month
    FROM {{ ref('fact_conversions') }}
    WHERE 1=1
    {% if is_incremental() %}
        AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(event_time::DATE) FROM {{ this }}))
    {% endif %}

),

subs_actions AS (

    SELECT
        a.event_time,
        a.subscription_action AS event_type,
        a.user_id,
        a.subscription_id,
        c.conversion_device_type,
        c.conversion_app_type,
        c.conversion_os_group,
        c.term_id,
        c.term_name,
        CASE
            WHEN a.billing_period = 'NON_RECURRING' AND c.term_name ILIKE '%annual%' THEN '1 year'
            WHEN a.billing_period = 'NON_RECURRING' AND c.term_name ILIKE '%month%' THEN '1 month'
            ELSE a.billing_period
        END AS billing_period,
        a.cart_turnovertaxfree AS transaction_value,
        a.subscription_period_number,
        c.geo_id,
        c.geo_country,
        c.geo_region,
        c.geo_city,
        c.cohort_month
    FROM {{ ref('stg_piano__subs_events_web') }} a
    JOIN conversions c  -- This join ensures we only get subscription actions for subscriptions that have converted
        ON a.subscription_id = c.subscription_id
    WHERE 1=1
        AND a.event_name ILIKE 'subscription.action%'
    {% if is_incremental() %}
        AND a.event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(event_time::DATE) FROM {{ this }}))
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
        {{ dbt_utils.generate_surrogate_key(['subscription_id', 'event_time', 'event_type']) }} AS subscription_action_id,
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

)

SELECT *
FROM mrr
ORDER BY user_id, event_time
