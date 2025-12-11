-- We stage both experience.action and experience.interaction events here
-- because they are semantically similar and have the same filtering criteria
{{ config(materialized="view") }}

SELECT
    event_id,
    event_name,
    event_time,
    visit_id,
    visit_time,
    visitor_id,
    user_id,
    event_url,
    page,
    card_name,
    experience_id,
    experience_name,
    template_id,
    template_name,
    ab_test_variant_name,
    term_offer_name,
    c1x_brand_relationship,
    c1x_checkout_abandonment,
    c1x_lts
FROM {{source('studios_piano', 'studios_piano_events')}}
WHERE 1=1
    AND event_time::DATE > '2025-06-25'
    AND site_id = 638824
    AND event_name IN ('experience.action', 'experience.interaction', 'subscription.select')
    AND (experience_name RLIKE '.*[0-9]{3} -.*' OR experience_name IS NULL)
    AND (term_offer_name IS NULL OR term_offer_name = 'BBC Subscription')
    AND LOWER(geo_country) IN ('united states')
    AND (app_type IN ('responsive', 'mobile-responsive') OR app_type IS NULL)
