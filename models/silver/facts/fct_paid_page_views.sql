{{
    config(
        materialized="table",
        tags=["fct", "marketing"]
    )
}}

SELECT
    -- keys
    pageview_id,
    ad_sk,
    geo_id,
    device_platform_id,
    visit_id,
    visitor_id,
    site_id,
    content_id,

    -- dates
    page_view_date,
    page_view_time,

    -- attributes
    agency,
    agency_resolved_from,
    ad_id,
    src_campaign,
    visitor_new_return,
    is_visit_bounce,
    ro_lower_bound_pct,
    lts_lower_bound_pct,
    content_pillar,
    content_section,
    content_type,
    page_content_type,
    page_title,
    browser_group,
    geo_country,
    geo_region,

    -- measures
    page_duration_seconds,
    visit_duration_seconds,
    newsletter_subscribe_count,
    subscription_select_count,
    vx_conversion_count
FROM {{ ref('int_marketing__paid_page_views') }}
