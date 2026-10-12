{{ config(
    materialized="view",
    tags=["piano", "staging"]
) }}

SELECT
    -- IDs
    event_id,
    site_id,
    visit_id,
    visitor_id,
    user_id,
    user_first_party_id,
    pageview_id,

    -- Event Info
    event_name,
    event_time,
    event_url,
    event_url_domain,
    event_url_full,
    event_collection_platform,

    -- Visit Info
    visit_time,
    visit_time_utc,
    visit_bounce,
    visit_converted,
    visit_duration,
    visit_implication_degree,
    visit_page_views,
    visit_sales,
    src,
    src_url,
    src_detail,
    src_bbc_team,

    -- URL Attribution Parameters
    {{ extract_url_param('event_url', 'at_bbc_team') }} AS at_bbc_team,

    -- Visit Entry/Exit
    visit_entry_aisle1,
    visit_entry_aisle2,
    visit_entry_aisle3,
    visit_entry_aisle4,
    visit_entry_aisle5,
    visit_entry_aisle6,
    visit_entry_site_level2,
    visit_entrypage,
    visit_entrypage_chapter1,
    visit_entrypage_chapter2,
    visit_entrypage_chapter3,
    visit_entrypage_dynamic_name,
    visit_entrypage_full_name,
    visit_exit_site_level2,
    visit_exitpage,
    visit_exitpage_chapter1,
    visit_exitpage_chapter2,
    visit_exitpage_chapter3,
    visit_exitpage_full_name,

    -- Page Info
    page,
    page_title,
    page_content_type,
    content_type,
    content_id,
    content_section,
    content_topic,
    content_pillar,
    date_published,
    url,

    -- Device / App
    {{ generate_app_type_id('app_type') }} AS app_type_id,
    {{ generate_device_type_id('device_type') }} AS device_type_id,
    {{ generate_os_group_id('os_group') }} AS os_group_id,

    -- Geography
    {{ generate_geo_id('geo_country', 'geo_region') }} AS geo_id,
    geo_country,
    geo_region,
    geo_city,

    -- Experience / Template
    conversion_id,
    experience_id,
    experience_name,
    experience_execution_id,
    card_id,
    card_name,
    card_action,
    template_id,
    template_name,
    ab_test_card_title,
    ab_test_variant_name,

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
    created_via_upgrade,

    -- C1X Fields
    c1x_lts,
    c1x_content_likely_to_convert,
    c1x_likelihood_to_register,
    c1x_likelihood_to_return,
    c1x_revenue_auto_optimization,
    c1x_brand_relationship,
    c1x_checkout_abandonment,
    c1x_subscription_length,
    c1x_subscription_tenure,
    c1x_expiring_subscribers

FROM {{ source('studios_piano', 'studios_piano_events') }}
