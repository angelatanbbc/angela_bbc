{{config(materialized="view")}}

SELECT
    event_id,
    event_name,
    event_time,
    user_id,
    site_id,
    term,
    term_offer_id,
    billing_period,
    trial_duration,
    subscription_id,
    subscription_action,
    subscription_period_number,
    cart_turnovertaxfree
FROM {{source('studios_piano', 'studios_piano_events')}}
WHERE 1=1
    AND event_time::DATE > '2025-06-25'
    AND site_id = 638824
    AND event_name ILIKE 'subscription.action%'
