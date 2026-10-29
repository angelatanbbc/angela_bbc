{{
    config(
        materialized="table",
        tags=["marketing", "tableau"]
    )
}}

WITH campaign_platforms AS (

    -- the platform a campaign's spend is on, so its page views, outcomes and credit get the same label
    SELECT
        LOWER(TRIM(campaign_name)) AS campaign_key,
        MIN(platform) AS platform
    FROM {{ ref('agg_marketing_paid_page_views') }}
    WHERE has_spend AND campaign_name IS NOT NULL
    GROUP BY LOWER(TRIM(campaign_name))

),

delivery AS (

    SELECT
        COALESCE(p.platform, cp.platform, 'meta') AS platform,
        p.date_day,
        IFF(p.has_page_view, COALESCE(p.src_campaign, '(none)'), COALESCE(p.campaign_name, '(none)')) AS src_campaign,
        p.funnel_stage,
        p.funnel_stage_v2,
        p.src_bbc_team,
        COUNT(p.pageview_id) AS page_views,
        COUNT(DISTINCT p.visit_id) AS visits,
        COUNT(DISTINCT p.visitor_id) AS visitor_days,
        SUM(COALESCE(p.spend_per_page_view, 0)) AS spend,
        SUM(COALESCE(p.impressions_per_page_view, 0)) AS impressions,
        SUM(COALESCE(p.clicks_per_page_view, 0)) AS clicks,
        SUM(COALESCE(p.subscription_select_count, 0)) AS subscription_selects,
        SUM(COALESCE(p.vx_conversion_count, 0)) AS purchases_on_page_view
    FROM {{ ref('agg_marketing_paid_page_views') }} p
    LEFT JOIN campaign_platforms cp ON cp.campaign_key = LOWER(TRIM(p.src_campaign))
    GROUP BY
        COALESCE(p.platform, cp.platform, 'meta'),
        p.date_day,
        IFF(p.has_page_view, COALESCE(p.src_campaign, '(none)'), COALESCE(p.campaign_name, '(none)')),
        p.funnel_stage,
        p.funnel_stage_v2,
        p.src_bbc_team

),

outcomes AS (

    SELECT
        COALESCE(cp.platform, 'meta') AS platform,
        f.first_paid_date AS date_day,
        f.src_campaign,
        f.funnel_stage,
        f.funnel_stage_v2,
        f.src_bbc_team,
        COUNT(DISTINCT visitor_id) AS arrivals,
        SUM(saw_paywall) AS saw_paywall,
        SUM(interacted) AS interacted,
        SUM(saw_offer) AS saw_offer,
        SUM(interacted_offer) AS interacted_offer,
        SUM(converted) AS converted,
        SUM(converted_via_paywall) AS converted_via_paywall,
        SUM(saw_paywall_same_visit) AS saw_paywall_same_visit,
        SUM(interacted_same_visit) AS interacted_same_visit,
        SUM(saw_offer_same_visit) AS saw_offer_same_visit,
        SUM(interacted_offer_same_visit) AS interacted_offer_same_visit,
        SUM(converted_same_visit) AS converted_same_visit,
        SUM(converted_via_paywall_same_visit) AS converted_via_paywall_same_visit,
        SUM(newsletter_signup) AS newsletter_signups,
        SUM(newsletter_signup_same_visit) AS newsletter_signups_same_visit,
        -- last-paid-touch: each conversion on ONE campaign row, so this sums to distinct converters
        SUM(IFF(is_last_paid_touch, 1, 0)) AS converted_last_touch,
        SUM(IFF(is_last_paid_touch AND (prior_tof_touch = 1 OR prior_mof_touch = 1), 1, 0))
            AS converted_last_touch_prior_upper
    FROM {{ ref('agg_marketing_visitor_funnel') }} f
    LEFT JOIN campaign_platforms cp ON cp.campaign_key = LOWER(TRIM(f.src_campaign))
    GROUP BY
        COALESCE(cp.platform, 'meta'),
        f.first_paid_date,
        f.src_campaign,
        f.funnel_stage,
        f.funnel_stage_v2,
        f.src_bbc_team

),

paid_touches AS (

    SELECT
        f.touchpoint_date,
        -- as in int_marketing__paid_visits: Meta's unfilled campaign placeholder takes the Meta ad's campaign
        COALESCE(
            IFF(CONTAINS(ct.campaign, '{') AND a.platform = 'meta', a.campaign_name, ct.campaign),
            ct.campaign,
            '(none)'
        ) AS src_campaign,
        ch.agency,
        f.position_weight,
        f.last_touch_weight
    FROM {{ ref('fct_attribution_touchpoints') }} f
    JOIN {{ ref('dim_channel') }} ch ON f.channel_sk = ch.channel_sk
    LEFT JOIN {{ ref('dim_campaign_tracking') }} ct ON f.campaign_tracking_sk = ct.campaign_tracking_sk
    LEFT JOIN {{ ref('dim_ad') }} a ON f.ad_sk = a.ad_sk
    WHERE f.is_paid_touch
        AND ch.agency IS NOT NULL

),

attributed AS (

    SELECT
        COALESCE(cp.platform, 'meta') AS platform,
        t.touchpoint_date AS date_day,
        t.src_campaign,
        {{ classify_funnel_stage('t.src_campaign') }} AS funnel_stage,
        {{ classify_funnel_stage_v2('t.src_campaign') }} AS funnel_stage_v2,
        t.agency AS src_bbc_team,
        SUM(t.position_weight) AS paid_attributed_subscriptions,
        SUM(t.last_touch_weight) AS paid_last_touch_subscriptions
    FROM paid_touches t
    LEFT JOIN campaign_platforms cp ON cp.campaign_key = LOWER(TRIM(t.src_campaign))
    GROUP BY COALESCE(cp.platform, 'meta'), t.touchpoint_date, t.src_campaign, t.agency

),

all_sides AS (

    SELECT
        platform,
        date_day,
        src_campaign,
        funnel_stage,
        funnel_stage_v2,
        src_bbc_team,
        spend,
        impressions,
        clicks,
        page_views,
        visits,
        visitor_days,
        subscription_selects,
        purchases_on_page_view,
        0 AS arrivals,
        0 AS saw_paywall,
        0 AS interacted,
        0 AS saw_offer,
        0 AS interacted_offer,
        0 AS converted,
        0 AS converted_via_paywall,
        0 AS saw_paywall_same_visit,
        0 AS interacted_same_visit,
        0 AS saw_offer_same_visit,
        0 AS interacted_offer_same_visit,
        0 AS converted_same_visit,
        0 AS converted_via_paywall_same_visit,
        0 AS newsletter_signups,
        0 AS newsletter_signups_same_visit,
        0 AS converted_last_touch,
        0 AS converted_last_touch_prior_upper,
        0 AS paid_attributed_subscriptions,
        0 AS paid_last_touch_subscriptions
    FROM delivery

    UNION ALL

    SELECT
        platform,
        date_day,
        src_campaign,
        funnel_stage,
        funnel_stage_v2,
        src_bbc_team,
        0 AS spend,
        0 AS impressions,
        0 AS clicks,
        0 AS page_views,
        0 AS visits,
        0 AS visitor_days,
        0 AS subscription_selects,
        0 AS purchases_on_page_view,
        arrivals,
        saw_paywall,
        interacted,
        saw_offer,
        interacted_offer,
        converted,
        converted_via_paywall,
        saw_paywall_same_visit,
        interacted_same_visit,
        saw_offer_same_visit,
        interacted_offer_same_visit,
        converted_same_visit,
        converted_via_paywall_same_visit,
        newsletter_signups,
        newsletter_signups_same_visit,
        converted_last_touch,
        converted_last_touch_prior_upper,
        0 AS paid_attributed_subscriptions,
        0 AS paid_last_touch_subscriptions
    FROM outcomes

    UNION ALL

    SELECT
        platform,
        date_day,
        src_campaign,
        funnel_stage,
        funnel_stage_v2,
        src_bbc_team,
        0 AS spend,
        0 AS impressions,
        0 AS clicks,
        0 AS page_views,
        0 AS visits,
        0 AS visitor_days,
        0 AS subscription_selects,
        0 AS purchases_on_page_view,
        0 AS arrivals,
        0 AS saw_paywall,
        0 AS interacted,
        0 AS saw_offer,
        0 AS interacted_offer,
        0 AS converted,
        0 AS converted_via_paywall,
        0 AS saw_paywall_same_visit,
        0 AS interacted_same_visit,
        0 AS saw_offer_same_visit,
        0 AS interacted_offer_same_visit,
        0 AS converted_same_visit,
        0 AS converted_via_paywall_same_visit,
        0 AS newsletter_signups,
        0 AS newsletter_signups_same_visit,
        0 AS converted_last_touch,
        0 AS converted_last_touch_prior_upper,
        paid_attributed_subscriptions,
        paid_last_touch_subscriptions
    FROM attributed

)

SELECT
    -- grain
    LEFT(platform, 16)::VARCHAR(16) AS platform,
    date_day,
    LEFT(src_campaign, 512)::VARCHAR(512) AS src_campaign,
    LEFT(funnel_stage, 3)::VARCHAR(3) AS funnel_stage,
    LEFT(funnel_stage_v2, 16)::VARCHAR(16) AS funnel_stage_v2,
    LEFT(src_bbc_team, 16)::VARCHAR(16) AS src_bbc_team,
    -- delivery and page-view engagement (day of the page view / ad-day)
    SUM(spend) AS spend,
    SUM(impressions) AS impressions,
    SUM(clicks) AS clicks,
    SUM(page_views) AS page_views,
    SUM(visits) AS visits,
    SUM(visitor_days) AS visitor_days,
    SUM(subscription_selects) AS subscription_selects,
    SUM(purchases_on_page_view) AS purchases_on_page_view,
    -- visitor outcomes (day the visitor first arrived on the campaign)
    SUM(arrivals) AS arrivals,
    SUM(saw_paywall) AS saw_paywall,
    SUM(interacted) AS interacted,
    SUM(saw_offer) AS saw_offer,
    SUM(interacted_offer) AS interacted_offer,
    SUM(converted) AS converted,
    SUM(converted_via_paywall) AS converted_via_paywall,
    SUM(saw_paywall_same_visit) AS saw_paywall_same_visit,
    SUM(interacted_same_visit) AS interacted_same_visit,
    SUM(saw_offer_same_visit) AS saw_offer_same_visit,
    SUM(interacted_offer_same_visit) AS interacted_offer_same_visit,
    SUM(converted_same_visit) AS converted_same_visit,
    SUM(converted_via_paywall_same_visit) AS converted_via_paywall_same_visit,
    SUM(newsletter_signups) AS newsletter_signups,
    SUM(newsletter_signups_same_visit) AS newsletter_signups_same_visit,
    SUM(converted_last_touch) AS converted_last_touch,
    SUM(converted_last_touch_prior_upper) AS converted_last_touch_prior_upper,
    -- the click-based attribution's paid credit (day of the click)
    SUM(paid_attributed_subscriptions) AS paid_attributed_subscriptions,
    SUM(paid_last_touch_subscriptions) AS paid_last_touch_subscriptions
FROM all_sides
GROUP BY platform, date_day, src_campaign, funnel_stage, funnel_stage_v2, src_bbc_team
