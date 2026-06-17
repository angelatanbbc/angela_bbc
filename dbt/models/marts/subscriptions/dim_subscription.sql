{{ config(materialized="table") }}

WITH subscription_events AS (

    SELECT *
    FROM {{ ref('fact_subscription_events') }}
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
        subscription_id,
        MAX(user_id) AS user_id,
        MAX(user_first_party_id) AS user_first_party_id,
        MIN_BY(conversion_id, event_time) AS conversion_id,
        BOOLOR_AGG(COALESCE(created_via_upgrade, FALSE)) AS created_via_upgrade,

        MIN(event_time) AS subscription_started_at,
        MAX(event_time) AS latest_subscription_event_at,
        MAX_BY(event_type, event_time) AS latest_subscription_action,

        MIN_BY(term_id, event_time) AS term_id,
        MIN_BY(term_name, event_time) AS term_name,
        MIN_BY(billing_period, event_time) AS billing_period,
        MAX_BY(subscription_period_number, event_time) AS subscription_period_number,

        MAX_BY(running_mrr_amount, event_time) AS final_running_mrr_amount
    FROM events_with_mrr
    GROUP BY subscription_id

),

sequenced AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY subscription_started_at, subscription_id
        ) AS subscription_sequence_number,
        LEAD(subscription_id) OVER (
            PARTITION BY user_id
            ORDER BY subscription_started_at, subscription_id
        ) AS next_subscription_id,
        LEAD(conversion_id) OVER (
            PARTITION BY user_id
            ORDER BY subscription_started_at, subscription_id
        ) AS next_conversion_id,
        LEAD(subscription_started_at) OVER (
            PARTITION BY user_id
            ORDER BY subscription_started_at, subscription_id
        ) AS next_subscription_started_at,
        LEAD(created_via_upgrade) OVER (
            PARTITION BY user_id
            ORDER BY subscription_started_at, subscription_id
        ) AS next_created_via_upgrade
    FROM subscription_lifecycle
    WHERE user_id IS NOT NULL

),

classified AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['subscription_id']) }} AS subscription_key,
        subscription_id,
        user_id,
        user_first_party_id,
        conversion_id,
        subscription_sequence_number,

        CASE
            WHEN created_via_upgrade THEN 'upgrade'
            WHEN subscription_sequence_number = 1 THEN 'brand_new'
            ELSE 're_subscription'
        END AS subscription_start_type,

        COALESCE(next_created_via_upgrade, FALSE) AS is_ended_by_upgrade,
        IFF(COALESCE(next_created_via_upgrade, FALSE), next_subscription_id, NULL) AS ended_by_upgrade_subscription_id,
        IFF(COALESCE(next_created_via_upgrade, FALSE), next_conversion_id, NULL) AS ended_by_upgrade_conversion_id,

        CASE
            WHEN COALESCE(next_created_via_upgrade, FALSE) THEN 'upgraded'
            WHEN COALESCE(final_running_mrr_amount, 0) > 0 THEN NULL
            WHEN latest_subscription_action = 'Canceled' THEN 'cancelled'
            WHEN latest_subscription_action = 'Renewal failed, will not retry' THEN 'payment_failed'
            WHEN latest_subscription_action = 'Expired' THEN 'expired'
            ELSE 'unknown'
        END AS subscription_end_type,

        NOT COALESCE(next_created_via_upgrade, FALSE)
            AND COALESCE(final_running_mrr_amount, 0) > 0 AS is_active,

        subscription_started_at,
        IFF(
            COALESCE(next_created_via_upgrade, FALSE),
            next_subscription_started_at,
            IFF(COALESCE(final_running_mrr_amount, 0) > 0, NULL, latest_subscription_event_at)
        ) AS subscription_ended_at,
        latest_subscription_event_at,
        latest_subscription_action,
        created_via_upgrade,

        term_id,
        term_name,
        billing_period,
        subscription_period_number,
        IFF(
            COALESCE(next_created_via_upgrade, FALSE),
            0,
            COALESCE(final_running_mrr_amount, 0)
        ) AS mrr_amount
    FROM sequenced

)

SELECT *
FROM classified
ORDER BY user_id, subscription_sequence_number
