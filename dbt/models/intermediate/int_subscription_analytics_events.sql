{{ config(
    materialized="view",
    tags=["piano", "intermediate"]
) }}

WITH subscriptions AS (

    SELECT
        subscription_id,
        user_id,
        user_first_party_id,
        subscription_started_at,
        subscription_ended_at
    FROM {{ ref('dim_subscription') }}
    WHERE user_id != 'unidentified-user'

),

analytics_events AS (

    SELECT *
    FROM {{ ref('stg_piano__analytics_events') }}
    WHERE
        user_id IS NOT NULL
        AND user_id != 'unidentified-user'

)

SELECT
    a.event_id,
    s.subscription_id,
    s.user_id,
    s.user_first_party_id,
    s.subscription_started_at,
    s.subscription_ended_at,
    a.* EXCLUDE (event_id, user_id, user_first_party_id)
FROM analytics_events a
JOIN subscriptions s
    ON a.user_id = s.user_id
    AND a.event_time >= s.subscription_started_at
    AND (
        a.event_time < s.subscription_ended_at
        OR s.subscription_ended_at IS NULL
    )
