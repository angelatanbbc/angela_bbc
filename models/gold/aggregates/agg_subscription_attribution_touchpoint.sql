{{
    config(
        materialized="table",
        tags=["attribution", "tableau"]
    )
}}

-- text is capped at VARCHAR(512) for Tableau's Snowflake driver
SELECT
    -- keys
    f.attribution_touchpoint_sk,
    f.conversion_id,
    f.subscription_id,
    f.pageview_id,
    f.site_id,

    -- dates
    f.touchpoint_date,
    f.touchpoint_at,
    f.conversion_date,
    f.conversion_at,

    -- the touch
    f.touchpoint_type,
    f.identity_link_type,
    f.agency_resolved_from,
    f.is_paid_touch,
    f.is_source_imputed,
    f.is_lookback_complete,
    LEFT(f.billing_period, 512)::VARCHAR(512) AS billing_period,

    -- channel
    LEFT(ch.channel_group, 512)::VARCHAR(512) AS channel_group,
    LEFT(ch.attribution_source, 512)::VARCHAR(512) AS attribution_source,
    LEFT(ch.attribution_source_detail, 512)::VARCHAR(512) AS attribution_source_detail,
    LEFT(ch.agency, 512)::VARCHAR(512) AS agency,
    LEFT(ch.bbc_team, 512)::VARCHAR(512) AS bbc_team,
    LEFT(ch.partner, 512)::VARCHAR(512) AS partner,
    LEFT(ch.piano_source, 512)::VARCHAR(512) AS piano_source,
    LEFT(ch.piano_source_detail, 512)::VARCHAR(512) AS piano_source_detail,

    -- campaign tags on the visit
    LEFT(ct.campaign, 512)::VARCHAR(512) AS campaign,
    LEFT(ct.ad_set_name, 512)::VARCHAR(512) AS ad_set_name,
    LEFT(ct.ad_set_id, 512)::VARCHAR(512) AS ad_set_id,
    LEFT(ct.creative_id, 512)::VARCHAR(512) AS creative_id,
    LEFT(ct.creation, 512)::VARCHAR(512) AS creation,
    LEFT(ct.objective, 512)::VARCHAR(512) AS objective,
    LEFT(ct.medium, 512)::VARCHAR(512) AS medium,
    LEFT(ct.keyword, 512)::VARCHAR(512) AS keyword,
    LEFT(ct.match_type, 512)::VARCHAR(512) AS match_type,
    LEFT(ct.campaign_type, 512)::VARCHAR(512) AS campaign_type,
    LEFT(ct.ad_format, 512)::VARCHAR(512) AS ad_format,
    LEFT(ct.link_origin, 512)::VARCHAR(512) AS link_origin,

    -- the Meta, Google or Microsoft ad, when the touch's creative id is a known ad
    LEFT(a.platform, 512)::VARCHAR(512) AS ad_platform,
    LEFT(a.ad_name, 512)::VARCHAR(512) AS platform_ad_name,
    LEFT(a.adset_name, 512)::VARCHAR(512) AS platform_ad_set_name,
    LEFT(a.campaign_name, 512)::VARCHAR(512) AS platform_campaign_name,
    LEFT(a.account_name, 512)::VARCHAR(512) AS platform_account_name,
    {{ classify_funnel_stage('a.campaign_name') }}::VARCHAR(3) AS funnel_stage,
    {{ classify_funnel_stage_v2('a.campaign_name') }}::VARCHAR(16) AS funnel_stage_v2,

    -- device, location and content of the touch
    LEFT(dt.device_type, 512)::VARCHAR(512) AS device_type,
    LEFT(og.os_group, 512)::VARCHAR(512) AS os_group,
    LEFT(f.browser_group, 512)::VARCHAR(512) AS browser_group,
    LEFT(f.geo_country, 512)::VARCHAR(512) AS geo_country,
    LEFT(f.geo_region, 512)::VARCHAR(512) AS geo_region,
    LEFT(f.content_pillar, 512)::VARCHAR(512) AS content_pillar,
    LEFT(f.content_section, 512)::VARCHAR(512) AS content_section,
    LEFT(f.content_type, 512)::VARCHAR(512) AS content_type,

    -- credit
    f.position_weight,
    f.signup_touch_weight,
    f.first_touch_weight,
    f.last_touch_weight
FROM {{ ref('fct_attribution_touchpoints') }} f
LEFT JOIN {{ ref('dim_channel') }} ch ON f.channel_sk = ch.channel_sk
LEFT JOIN {{ ref('dim_campaign_tracking') }} ct ON f.campaign_tracking_sk = ct.campaign_tracking_sk
LEFT JOIN {{ ref('dim_ad') }} a ON f.ad_sk = a.ad_sk
LEFT JOIN {{ ref('dim_device_type') }} dt ON f.device_type_id = dt.device_type_id
LEFT JOIN {{ ref('dim_os_group') }} og ON f.os_group_id = og.os_group_id
