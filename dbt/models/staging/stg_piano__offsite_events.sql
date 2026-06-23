{{ config(
    materialized="view",
    tags=["piano", "staging"]
) }}


SELECT
    -- IDs
    event_id,
    site_id,
    user_id,
    user_first_party_id,

    -- Event Info
    event_name,
    event_time,

    -- Experience / Template
    conversion_id,

    -- Subscription / Commercial
    subscription_id,
    term[0]['term_id2']::STRING AS term_id,
    term[0]['term_name']::STRING AS term_name,
    term_offer_id,
    term_offer_name,
    billing_period,
    trial_duration,
    vx_promo_code,
    cart_turnovertaxfree,
    subscription_action,
    subscription_period_number,
    created_via_upgrade

FROM {{ source('studios_piano', 'studios_piano_events') }}

WHERE
    site_id = 638824
    AND event_time::DATE > '2025-06-25'
    AND event_name IN ('vx.conversion.offsite',
                       'subscription.action.offsite',
                       'transaction.refund.offsite')
