{{
    config(
        materialized="table",
        tags=['fct', 'subscriptions']
    )
}}

WITH conversions AS (

    SELECT
        conversion_id,
        conversion_time AS event_time,
        conversion_time::DATE AS event_date,
        IFF(created_via_upgrade, 'Upgraded subscription', 'New subscription') AS subscription_action,
        user_id,
        user_first_party_id,
        subscription_id,
        created_via_upgrade,
        app_type_id AS conversion_app_type_id,
        device_type_id AS conversion_device_type_id,
        os_group_id AS conversion_os_group_id,
        term_id,
        term_name,
        billing_period,
        subscription_period_number,
        geo_id,
        geo_country,
        geo_region,
        geo_city,
        cohort_month,
        cart_turnovertaxfree AS transaction_value
    FROM {{ ref('fact_conversions') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY conversion_id ORDER BY event_time DESC) = 1

),

-- For auto-renew disables, upgrade schedules and upgrade completions
subs_actions_onsite AS (

    SELECT
        c.conversion_id,
        a.event_time,
        a.event_time::DATE AS event_date,
        a.subscription_action,
        a.user_id,
        a.user_first_party_id,
        a.subscription_id,
        c.created_via_upgrade,
        c.conversion_app_type_id,
        c.conversion_device_type_id,
        c.conversion_os_group_id,
        c.term_id,
        c.term_name,
        CASE
            WHEN a.billing_period = 'NON_RECURRING' AND c.term_name ILIKE '%annual%' THEN '1 year'
            WHEN a.billing_period = 'NON_RECURRING' AND c.term_name ILIKE '%month%' THEN '1 month'
            ELSE a.billing_period
        END AS billing_period,
        a.subscription_period_number,
        c.geo_id,
        c.geo_country,
        c.geo_region,
        c.geo_city,
        c.cohort_month,
        a.cart_turnovertaxfree AS transaction_value
    FROM {{ ref('stg_piano__studios_events') }} a
    JOIN conversions c USING (subscription_id)
    WHERE 1=1
        AND a.site_id = 638824
        AND a.event_time::DATE > '2025-06-25'
        AND a.event_name = 'subscription.action'

),

subs_actions_offsite AS (

    SELECT
        c.conversion_id,
        a.event_time,
        a.event_time::DATE AS event_date,
        a.subscription_action,
        a.user_id,
        a.user_first_party_id,
        a.subscription_id,
        c.created_via_upgrade,
        c.conversion_app_type_id,
        c.conversion_device_type_id,
        c.conversion_os_group_id,
        c.term_id,
        c.term_name,
        CASE
            WHEN a.billing_period = 'NON_RECURRING' AND c.term_name ILIKE '%annual%' THEN '1 year'
            WHEN a.billing_period = 'NON_RECURRING' AND c.term_name ILIKE '%month%' THEN '1 month'
            ELSE a.billing_period
        END AS billing_period,
        a.subscription_period_number,
        c.geo_id,
        c.geo_country,
        c.geo_region,
        c.geo_city,
        c.cohort_month,
        a.cart_turnovertaxfree AS transaction_value
    FROM {{ ref('stg_piano__studios_events') }} a
    JOIN conversions c  -- This join ensures we only get subscription actions for subscriptions that have converted
        ON a.subscription_id = c.subscription_id
    WHERE 1=1
        AND a.site_id = 638824
        AND a.event_time::DATE > '2025-06-25'
        AND a.event_name = 'subscription.action.offsite'

),

unioned AS (

    SELECT *
    FROM conversions

    UNION ALL

    SELECT *
    FROM subs_actions_onsite

    UNION ALL

    SELECT *
    FROM subs_actions_offsite

),

mrr AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['subscription_id', 'event_time', 'subscription_action']) }} AS subscription_action_id,
        *,
        LAG(transaction_value) IGNORE NULLS OVER (
            PARTITION BY subscription_id
            ORDER BY event_time
        ) AS previous_transaction_value,
        ZEROIFNULL(IFF(billing_period ILIKE '%year%', previous_transaction_value / 12, previous_transaction_value)) AS previous_mrr, 

        CASE
            WHEN subscription_action IN ('New subscription', 'Upgraded subscription') THEN IFF(billing_period ILIKE '%year%', transaction_value / 12, transaction_value)
            WHEN subscription_action = 'Renewed' AND billing_period ILIKE '%month%' THEN transaction_value - previous_mrr
            WHEN subscription_action = 'Renewed' AND billing_period ILIKE '%year%' THEN (transaction_value / 12) - previous_mrr
            WHEN subscription_action IN ('Canceled', 'Expired', 'Renewal failed, will not retry', 'Upgrade completed') THEN -previous_mrr
            ELSE 0
        END AS mrr_change_amount,
        previous_mrr + mrr_change_amount AS current_mrr
    FROM unioned

)

SELECT *
FROM mrr
ORDER BY user_id, event_time
