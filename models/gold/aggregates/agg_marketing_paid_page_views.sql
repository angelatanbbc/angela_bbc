{{
    config(
        materialized="table",
        tags=["marketing", "tableau"]
    )
}}

WITH spend AS (

    SELECT
        f.spend_date AS date_day,
        f.platform,
        f.account_id,
        f.ad_id,
        f.adset_id,
        f.campaign_id,
        f.account_currency,
        f.impressions,
        f.link_clicks AS clicks,
        f.spend_amount AS spend,
        a.ad_name,
        a.adset_name,
        a.campaign_name,
        a.bbc_team
    FROM {{ ref('fct_ad_performance_daily') }} f
    LEFT JOIN {{ ref('dim_ad') }} a ON f.ad_sk = a.ad_sk
    {%- if not var('include_podcast_ads') %}
    WHERE NOT COALESCE(a.is_podcast_ad, FALSE)
    {%- endif %}

),

page_views AS (

    SELECT
        p.pageview_id,
        p.visit_id,
        p.visitor_id,
        p.site_id,
        p.page_view_date,
        p.page_view_time,
        p.agency,
        p.agency_resolved_from,
        p.ad_id,
        p.src_campaign,
        p.visitor_new_return,
        p.is_visit_bounce,
        p.ro_lower_bound_pct,
        p.page_duration_seconds,
        p.visit_duration_seconds,
        p.newsletter_subscribe_count,
        p.subscription_select_count,
        p.vx_conversion_count,
        p.content_id,
        p.content_pillar,
        p.content_section,
        p.content_type,
        p.page_content_type,
        p.page_title,
        dp.device_type,
        dp.os_group,
        p.browser_group,
        p.geo_country,
        p.geo_region
    FROM {{ ref('fct_paid_page_views') }} p
    LEFT JOIN {{ ref('dim_device_platform') }} dp ON p.device_platform_id = dp.device_platform_id
    WHERE p.ad_id IS NOT NULL

),

page_views_per_ad_day AS (

    SELECT
        page_view_date AS date_day,
        ad_id,
        COUNT(*) AS page_views_on_ad_day
    FROM page_views
    GROUP BY page_view_date, ad_id

),

joined AS (

    SELECT
        COALESCE(s.date_day, pv.page_view_date) AS date_day,
        COALESCE(s.ad_id, pv.ad_id) AS ad_id,
        pv.pageview_id,
        s.ad_id IS NOT NULL AS has_spend,
        pv.pageview_id IS NOT NULL AS has_page_view,
        s.platform,
        s.account_id,
        s.ad_name,
        s.adset_id,
        s.adset_name,
        s.campaign_id,
        s.campaign_name,
        -- the visit's agency where there is a page view, else the ad's
        COALESCE(pv.agency, s.bbc_team) AS src_bbc_team,
        -- the page view's stage (Piano's src_campaign), else the ad's (the platform's campaign name)
        COALESCE({{ classify_funnel_stage('pv.src_campaign') }}, {{ classify_funnel_stage('s.campaign_name') }}) AS funnel_stage,
        COALESCE({{ classify_funnel_stage_v2('pv.src_campaign') }}, {{ classify_funnel_stage_v2('s.campaign_name') }})
            AS funnel_stage_v2,
        s.account_currency AS currency,
        s.impressions,
        s.clicks,
        s.spend,
        COALESCE(n.page_views_on_ad_day, 0) AS page_views_on_ad_day,
        -- the ad-day's totals split equally across its page views; an ad-day without any keeps them whole
        s.impressions / COALESCE(NULLIF(n.page_views_on_ad_day, 0), 1) AS impressions_per_page_view,
        s.clicks / COALESCE(NULLIF(n.page_views_on_ad_day, 0), 1) AS clicks_per_page_view,
        s.spend / COALESCE(NULLIF(n.page_views_on_ad_day, 0), 1) AS spend_per_page_view,
        pv.visitor_id,
        pv.visit_id,
        pv.site_id,
        pv.page_view_date,
        pv.page_view_time,
        pv.agency_resolved_from,
        pv.src_campaign,
        pv.visitor_new_return,
        pv.is_visit_bounce,
        pv.ro_lower_bound_pct,
        pv.page_duration_seconds,
        pv.visit_duration_seconds,
        pv.newsletter_subscribe_count,
        pv.subscription_select_count,
        pv.vx_conversion_count,
        pv.content_id,
        pv.content_pillar,
        pv.content_section,
        pv.content_type,
        pv.page_content_type,
        pv.page_title,
        pv.device_type,
        pv.os_group,
        pv.browser_group,
        pv.geo_country,
        pv.geo_region
    FROM spend s
    FULL OUTER JOIN page_views_per_ad_day n
        ON s.date_day = n.date_day
        AND s.ad_id = n.ad_id
    FULL OUTER JOIN page_views pv
        ON COALESCE(s.date_day, n.date_day) = pv.page_view_date
        AND COALESCE(s.ad_id, n.ad_id) = pv.ad_id

)

SELECT
    -- keys
    date_day,
    LEFT(ad_id, 64)::VARCHAR(64) AS ad_id,
    LEFT(pageview_id, 512)::VARCHAR(512) AS pageview_id,
    HEX_ENCODE(visitor_id)::VARCHAR(64) AS visitor_id,
    HEX_ENCODE(visit_id)::VARCHAR(64) AS visit_id,
    has_spend,
    has_page_view,

    -- the ad (spend side)
    LEFT(platform, 16)::VARCHAR(16) AS platform,
    LEFT(account_id, 64)::VARCHAR(64) AS account_id,
    LEFT(ad_name, 512)::VARCHAR(512) AS ad_name,
    LEFT(adset_id, 64)::VARCHAR(64) AS adset_id,
    LEFT(adset_name, 512)::VARCHAR(512) AS adset_name,
    LEFT(campaign_id, 64)::VARCHAR(64) AS campaign_id,
    LEFT(campaign_name, 512)::VARCHAR(512) AS campaign_name,
    LEFT(src_bbc_team, 16)::VARCHAR(16) AS src_bbc_team,
    LEFT(funnel_stage, 3)::VARCHAR(3) AS funnel_stage,
    LEFT(funnel_stage_v2, 16)::VARCHAR(16) AS funnel_stage_v2,
    LEFT(currency, 8)::VARCHAR(8) AS currency,

    -- ad-day totals (not additive across the page views of one ad-day)
    impressions,
    clicks,
    spend,
    page_views_on_ad_day,

    -- the equal split (additive)
    impressions_per_page_view,
    clicks_per_page_view,
    spend_per_page_view,

    -- the page view
    site_id,
    page_view_date,
    page_view_time,
    LEFT(src_campaign, 512)::VARCHAR(512) AS src_campaign,
    LEFT(agency_resolved_from, 16)::VARCHAR(16) AS agency_resolved_from,
    LEFT(visitor_new_return, 16)::VARCHAR(16) AS visitor_new_return,
    is_visit_bounce AS visit_bounce,
    ro_lower_bound_pct,
    CASE
        WHEN NOT has_page_view THEN NULL
        WHEN ro_lower_bound_pct IS NULL THEN 'No score'
        WHEN ro_lower_bound_pct >= {{ var('high_ro_threshold') }} THEN 'RevOps 80+'
        WHEN ro_lower_bound_pct >= {{ var('med_ro_threshold') }} THEN 'RevOps 50-79'
        ELSE 'RevOps <50'
    END::VARCHAR(16) AS ro_band,
    page_duration_seconds,
    visit_duration_seconds,
    newsletter_subscribe_count,
    subscription_select_count,
    vx_conversion_count,

    -- content, device and geography of the page view
    LEFT(content_id, 512)::VARCHAR(512) AS content_id,
    LEFT(content_pillar, 512)::VARCHAR(512) AS content_pillar,
    LEFT(content_section, 512)::VARCHAR(512) AS content_section,
    LEFT(content_type, 512)::VARCHAR(512) AS content_type,
    LEFT(page_content_type, 512)::VARCHAR(512) AS page_content_type,
    LEFT(page_title, 512)::VARCHAR(512) AS page_title,
    LEFT(device_type, 64)::VARCHAR(64) AS device_type,
    LEFT(os_group, 64)::VARCHAR(64) AS os_group,
    LEFT(browser_group, 64)::VARCHAR(64) AS browser_group,
    LEFT(geo_country, 128)::VARCHAR(128) AS geo_country,
    LEFT(geo_region, 128)::VARCHAR(128) AS geo_region
FROM joined
