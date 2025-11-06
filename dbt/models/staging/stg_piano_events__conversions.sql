{{config(materialized="view")}}

SELECT
    event_id,
    event_time,
    visit_id,
    visit_time,
    visitor_id,
    user_id,
    device_type,
    pageview_id,
    page,
    page_content_type,
    event_url,
    card_name,
    experience_id,
    experience_name,
    template_id,
    template_name,
    ab_test_variant_name,
    term,
    term_offer_id,
    term_offer_name,
    billing_period,
    trial_duration,
    vx_promo_code,
    c1x_brand_relationship,
    c1x_checkout_abandonment,
    c1x_lts,
    conversion_id,
    subscription_id,
    subscription_action,
    subscription_period_number,
    g.geo_id
FROM {{source('studios_piano', 'studios_piano_events')}} e
LEFT JOIN {{ ref('dim_geography') }} g
    ON LOWER(e.geo_country) = LOWER(g.geo_country)
    AND LOWER(e.geo_region) = LOWER(g.geo_region)
WHERE 1=1
    AND event_time::DATE > '2025-06-25'
    AND site_id = 638824
    AND event_name = 'vx.conversion'
    AND (experience_name LIKE '%00%' OR experience_name IS NULL)
    AND (term_offer_name IS NULL OR term_offer_name = 'BBC Subscription')
    AND LOWER(e.geo_country) IN ('united states')
    AND (app_type IN ('responsive', 'mobile-responsive') OR app_type IS NULL)
