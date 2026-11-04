{{
    config(
        materialized="table",
        tags=['subscriptions', 'piano', 'mart', 'dim']
    )
}}

WITH subscription_latest_snapshot AS (

    SELECT
        subscription_id,
        NULL AS user_id,
        user_uid AS user_first_party_id,
        status,
        status_name,
        auto_renew,
        cancellable,
        cancellable_and_refundable,
        billing_plan,
        term_id,
        term_name,
        resource_rid AS resource_id,
        resource_name AS resource_name,
        start_date,
        end_date,
        next_bill_date AS next_billing_at,
        is_in_trial,
        trial_period_end_date,
        trial_amount,
        trial_currency,
        charge_count,
        user_create_date,
        user_last_visit
    FROM {{ ref('int_piano__subscription_current') }}

),

terms AS (

    SELECT
        term_id,
        billing_channel,
        billing_country
    FROM {{ ref('dim_term') }}

),

subscription_events AS (

    SELECT *
    FROM {{ ref('fct_subscription_events') }}
    WHERE subscription_id IS NOT NULL

),

events_with_mrr AS (

    SELECT
        *,
        SUM(mrr_change_amount) OVER (
            PARTITION BY subscription_id
            ORDER BY event_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_mrr_amount
    FROM subscription_events

),

subscription_lifecycle AS (

    SELECT
        s.*,
        MAX(e.billing_period) AS billing_period,
        MIN_BY(e.conversion_id, event_time) AS conversion_id,
        MIN_BY(e.conversion_device_platform_id, e.event_time) AS conversion_device_platform_id,
        MIN_BY(e.conversion_payment_provider, e.event_time) AS conversion_payment_provider,
        MIN_BY(e.conversion_card_brand, e.event_time) AS conversion_card_brand,
        MIN_BY(e.cohort_month, e.event_time) AS cohort_month,
        MIN_BY(e.geo_country, e.event_time) AS conversion_geo_country,
        BOOLOR_AGG(COALESCE(e.created_via_upgrade, FALSE)) AS created_via_upgrade,
        MAX(e.event_time) AS latest_action_at,
        MAX_BY(e.subscription_action, e.event_time) AS latest_action,
        MAX_BY(e.subscription_period_number, e.event_time) AS subscription_period_number,
        MAX_BY(e.running_mrr_amount, e.event_time) AS final_running_mrr_amount
    FROM subscription_latest_snapshot s
    LEFT JOIN events_with_mrr e USING (subscription_id)
    GROUP BY ALL

),

sequenced AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_first_party_id
            ORDER BY start_date, subscription_id
        ) AS subscription_sequence_number,
        LEAD(subscription_id) OVER (
            PARTITION BY user_first_party_id
            ORDER BY start_date, subscription_id
        ) AS next_subscription_id,
        LEAD(conversion_id) OVER (
            PARTITION BY user_first_party_id
            ORDER BY start_date, subscription_id
        ) AS next_conversion_id,
        LEAD(end_date) OVER (
            PARTITION BY user_first_party_id
            ORDER BY start_date, subscription_id
        ) AS next_subscription_ended_at,
        LEAD(start_date) OVER (
            PARTITION BY user_first_party_id
            ORDER BY start_date, subscription_id
        ) AS next_subscription_started_at,
        LEAD(created_via_upgrade) OVER (
            PARTITION BY user_first_party_id
            ORDER BY start_date, subscription_id
        ) AS next_created_via_upgrade
    FROM subscription_lifecycle
    WHERE user_first_party_id IS NOT NULL

),

-- Subscriptions are only sold in the United States and Canada. Web checkout
-- terms are priced per country, so the term gives the country. App store terms
-- cover both, so the conversion's geo tracking is the best estimate; tracking
-- is patchy, so anything it doesn't place in Canada counts as United states.
located AS (

    SELECT
        s.*,
        COALESCE(
            t.billing_country,
            IFF(s.conversion_geo_country = 'Canada', 'Canada', 'United states')
        ) AS subscription_country,
        t.billing_country IS NULL AS is_subscription_country_estimated,
        -- Subscriptions with no conversion event take App store from the term's
        -- billing channel; any other is Unknown.
        COALESCE(
            s.conversion_card_brand,
            IFF(t.billing_channel IN ('Apple App Store', 'Google Play'), 'App store', 'Unknown')
        ) AS conversion_card_brand_filled
    FROM sequenced s
    LEFT JOIN terms t
        ON s.term_id = t.term_id

),

classified AS (

    SELECT
        subscription_id,
        user_id,
        user_first_party_id,
        user_create_date,
        user_last_visit,
        conversion_id,
        conversion_device_platform_id,
        conversion_payment_provider,
        conversion_card_brand_filled AS conversion_card_brand,
        cohort_month,
        subscription_country,
        is_subscription_country_estimated,
        status,
        status_name,
        IFF(status = 'active', TRUE, FALSE) AS is_active,
        subscription_sequence_number,
        auto_renew,
        cancellable,
        cancellable_and_refundable,
        resource_id,
        resource_name,
        
        start_date AS subscription_started_at,
        CASE
            WHEN created_via_upgrade THEN 'Upgrade'
            WHEN subscription_sequence_number = 1 THEN 'Brand New'
            ELSE 'Re-subscription'
        END AS subscription_start_type,
        created_via_upgrade,

        end_date AS subscription_ended_at,
        IFF(status = 'active', next_billing_at, NULL) AS next_billing_at,
        COALESCE(next_created_via_upgrade, FALSE) AS is_ended_by_upgrade,
        IFF(COALESCE(next_created_via_upgrade, FALSE), next_subscription_id, NULL) AS ended_by_upgrade_subscription_id,
        IFF(COALESCE(next_created_via_upgrade, FALSE), next_conversion_id, NULL) AS ended_by_upgrade_conversion_id,
        CASE
            WHEN COALESCE(next_created_via_upgrade, FALSE) THEN 'Upgraded'
            WHEN COALESCE(final_running_mrr_amount, 0) > 0 THEN NULL
            WHEN latest_action IN ('Canceled', 'Renewal failed, will not retry', 'Expired') THEN latest_action
            ELSE 'Unknown'
        END AS subscription_end_type,

        is_in_trial,
        trial_period_end_date,
        trial_amount,
        trial_currency,

        latest_action_at,
        latest_action,

        term_id,
        term_name,
        billing_plan,
        billing_period,
        subscription_period_number,
        charge_count,
        IFF(
            COALESCE(next_created_via_upgrade, FALSE),
            0,
            COALESCE(final_running_mrr_amount, 0)
        ) AS mrr_amount
    FROM located

)

SELECT *
FROM classified
ORDER BY user_first_party_id, subscription_sequence_number
