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
    device_type,
    pageview_id,
    page,
    page_content_type,
    event_url,
    card_name,
    experience_name,
    CASE
        WHEN template_name = 'FINAL: The Gate - Default Template' THEN 'The Gate'
        WHEN template_name = 'FINAL: Ribbon - Default Template' AND experience_name = '004 - Ribbon' THEN 'Index Ribbon'
        WHEN template_name = 'FINAL: Ribbon - Default Template' AND experience_name = '006 - Watch Live News Meter' THEN 'Watch Live News Ribbon'
        ELSE  template_name
    END AS template_name,  -- TODO: Not sure we should be doing this mapping here, need to dicuss with team
    ab_test_variant_name,
    term_offer_name,
    c1x_brand_relationship,
    c1x_checkout_abandonment,
    c1x_lts,
    src,
    src_detail
FROM {{source('studios_piano', 'studios_piano_events')}}
WHERE 1=1
    AND event_time::DATE > '2025-06-25'
    AND site_id = 638824
    AND event_name IN ('experience.action', 'experience.interaction', 'subscription.select')
    AND (experience_name LIKE '%00%' OR experience_name IS NULL)
    AND (term_offer_name IS NULL OR term_offer_name = 'BBC Subscription')
    AND LOWER(geo_country) IN ('united states')
    AND (app_type IN ('responsive', 'mobile-responsive') OR app_type IS NULL)
