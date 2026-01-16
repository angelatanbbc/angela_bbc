{{ config(materialized="view") }}

SELECT
    -- IDs
    event_id,
    site_id,
    visit_id,
    visitor_id,
    user_id,
    pageview_id,
    
    -- Event Info
    event_name,
    event_time,
    event_url,
    
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
    src_detail,
    
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
    
    -- Device / App
    device_type,
    app_type,
    os_group,
    
    -- Geography
    {{ dbt_utils.generate_surrogate_key(['geo_country', 'geo_region']) }} AS geo_id,
    geo_country,
    geo_region,
    geo_city,
    
    -- Experience / Template
    conversion_id,
    experience_id,
    experience_name,
    card_id,
    card_name,
    card_action,
    template_id,
    template_name,
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
    subscription_period_number

FROM {{ source('studios_piano', 'studios_piano_events') }} e

WHERE 
    e.event_time::DATE >= '2026-01-05'
    AND e.site_id = 638824
    AND event_name IN ('page.display', 'vx.conversion', 'experience.action', 'experience.interaction', 'subscription.select')
    AND LOWER(geo_country) = 'united states'
    AND app_type = 'mobile-app'
