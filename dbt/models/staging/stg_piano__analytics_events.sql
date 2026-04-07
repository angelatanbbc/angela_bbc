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
    pageview_id,

    -- Event Info
    event_name,
    event_time,
    event_url,
    event_url_domain,
    event_url_full,

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
    content_id,

    -- Device / App
    {{ clean_device_type('device_type') }} AS device_type,
    {{ clean_app_type('app_type') }} AS app_type,
    {{ clean_os_group('os_group') }} AS os_group,

    -- Geography
    {{ dbt_utils.generate_surrogate_key(['geo_country', 'geo_region']) }} AS geo_id,
    geo_country,
    geo_region,
    geo_city,

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

WHERE
    site_id = 638824
    AND event_time::DATE > '2025-06-25'
    AND event_name = 'page.display'
