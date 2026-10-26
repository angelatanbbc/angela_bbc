{{
    config(
        materialized="table",
        tags=["fct", "marketing"]
    )
}}

WITH paid_page_views AS (

    SELECT
        pageview_id,
        visit_id,
        visitor_id,
        user_id,
        device_first_party_id,
        page_view_time,
        COALESCE(src_campaign, '(none)') AS src_campaign,
        agency,
        ro_lower_bound_pct,
        content_pillar
    FROM {{ ref('int_marketing__paid_page_views') }}
    WHERE visitor_id IS NOT NULL

),

events AS (

    SELECT
        event_id,
        pageview_id,
        visit_id,
        visitor_id,
        user_id,
        device_first_party_id,
        event_time,
        is_paywall,
        is_paywall_interaction,
        is_offer,
        is_offer_interaction,
        is_conversion,
        is_paywall_conversion,
        is_newsletter
    FROM {{ ref('int_marketing__funnel_events') }}

),

visitor_campaign AS (

    SELECT
        visitor_id,
        src_campaign,
        {{ classify_funnel_stage('src_campaign') }} AS funnel_stage,
        {{ classify_funnel_stage_v2('src_campaign') }} AS funnel_stage_v2,
        MAX(agency) AS agency,
        MIN(page_view_time) AS first_paid_time,
        COUNT(*) AS paid_page_views,
        MAX(ro_lower_bound_pct) AS ro_best_lower_bound_campaign,
        MIN_BY(content_pillar, page_view_time) AS landing_content_pillar
    FROM paid_page_views
    GROUP BY visitor_id, src_campaign

),

visitor AS (

    SELECT
        visitor_id,
        MIN(page_view_time) AS first_paid_time_visitor,
        MAX(ro_lower_bound_pct) AS ro_best_lower_bound_visitor
    FROM paid_page_views
    GROUP BY visitor_id

),

-- link 1: events on the visitor's paid page views, kept per campaign
on_paid_page_views AS (

    SELECT
        p.visitor_id,
        p.src_campaign,
        e.event_id,
        e.event_time,
        e.user_id,
        e.is_paywall,
        e.is_paywall_interaction,
        e.is_offer,
        e.is_offer_interaction,
        e.is_conversion,
        e.is_paywall_conversion,
        e.is_newsletter
    FROM paid_page_views p
    JOIN events e ON p.pageview_id = e.pageview_id

),

identity AS (

    SELECT DISTINCT
        visitor_id,
        user_id
    FROM paid_page_views
    WHERE user_id IS NOT NULL

    UNION DISTINCT

    SELECT DISTINCT
        visitor_id,
        user_id
    FROM on_paid_page_views
    WHERE user_id IS NOT NULL

),

paid_devices AS (

    SELECT
        visitor_id,
        MAX(device_first_party_id) AS device_id
    FROM paid_page_views
    WHERE device_first_party_id IS NOT NULL
    GROUP BY visitor_id

),

-- a browser carrying many paid visitor_ids is shared, not one person
usable_devices AS (

    SELECT device_id
    FROM paid_devices
    GROUP BY device_id
    HAVING COUNT(DISTINCT visitor_id) <= {{ var('attribution_max_cookies_per_browser') }}

),

linked_over_time AS (

    SELECT
        visitor_id,
        event_id,
        event_time,
        is_paywall,
        is_paywall_interaction,
        is_offer,
        is_offer_interaction,
        is_conversion,
        is_paywall_conversion,
        is_newsletter,
        1 AS link
    FROM on_paid_page_views

    UNION ALL

    -- link 2: same visitor_id afterwards
    SELECT
        v.visitor_id,
        e.event_id,
        e.event_time,
        e.is_paywall,
        e.is_paywall_interaction,
        e.is_offer,
        e.is_offer_interaction,
        e.is_conversion,
        e.is_paywall_conversion,
        e.is_newsletter,
        2 AS link
    FROM visitor v
    JOIN events e
        ON v.visitor_id = e.visitor_id
        AND e.event_time >= v.first_paid_time_visitor

    UNION ALL

    -- link 3: same real account afterwards
    SELECT
        v.visitor_id,
        e.event_id,
        e.event_time,
        e.is_paywall,
        e.is_paywall_interaction,
        e.is_offer,
        e.is_offer_interaction,
        e.is_conversion,
        e.is_paywall_conversion,
        e.is_newsletter,
        3 AS link
    FROM visitor v
    JOIN identity i ON v.visitor_id = i.visitor_id
    JOIN events e
        ON i.user_id = e.user_id
        AND e.event_time >= v.first_paid_time_visitor

    UNION ALL

    -- link 4: same browser afterwards (shared browsers skipped)
    SELECT
        v.visitor_id,
        e.event_id,
        e.event_time,
        e.is_paywall,
        e.is_paywall_interaction,
        e.is_offer,
        e.is_offer_interaction,
        e.is_conversion,
        e.is_paywall_conversion,
        e.is_newsletter,
        4 AS link
    FROM visitor v
    JOIN paid_devices d ON v.visitor_id = d.visitor_id
    JOIN usable_devices u ON d.device_id = u.device_id
    JOIN events e
        ON d.device_id = e.device_first_party_id
        AND e.event_time >= v.first_paid_time_visitor

),

visitor_flags AS (

    SELECT
        visitor_id,
        MAX(is_paywall) AS saw_paywall,
        MAX(is_paywall_interaction) AS interacted,
        MAX(is_offer) AS saw_offer,
        MAX(is_offer_interaction) AS interacted_offer,
        MAX(is_conversion) AS converted,
        MAX(is_paywall_conversion) AS converted_via_paywall,
        MIN(IFF(is_paywall = 1, event_time, NULL)) AS first_paywall_time,
        MIN(IFF(is_paywall_interaction = 1, event_time, NULL)) AS first_interaction_time,
        MIN(IFF(is_offer = 1, event_time, NULL)) AS first_offer_time,
        MIN(IFF(is_offer_interaction = 1, event_time, NULL)) AS first_offer_interaction_time,
        MIN(IFF(is_conversion = 1, event_time, NULL)) AS first_conversion_time,
        MIN(IFF(is_paywall_conversion = 1, event_time, NULL)) AS first_paywall_conversion_time,
        MAX(is_newsletter) AS newsletter_signup,
        MIN(IFF(is_newsletter = 1, event_time, NULL)) AS first_newsletter_time,
        IFF(
            MAX(IFF(is_conversion = 1 AND link = 4, 1, 0)) = 1
            AND MAX(IFF(is_conversion = 1 AND link < 4, 1, 0)) = 0,
            1,
            0
        ) AS converted_browser_link_only
    FROM linked_over_time
    GROUP BY visitor_id

),

campaign_flags AS (

    SELECT
        visitor_id,
        src_campaign,
        MAX(is_paywall) AS saw_paywall_same_visit,
        MAX(is_paywall_interaction) AS interacted_same_visit,
        MAX(is_offer) AS saw_offer_same_visit,
        MAX(is_offer_interaction) AS interacted_offer_same_visit,
        MAX(is_conversion) AS converted_same_visit,
        MAX(is_paywall_conversion) AS converted_via_paywall_same_visit
    FROM on_paid_page_views
    GROUP BY visitor_id, src_campaign

),

paid_visits AS (

    SELECT DISTINCT
        visitor_id,
        src_campaign,
        visit_id
    FROM paid_page_views
    WHERE visit_id IS NOT NULL

),

-- a sign-up during one of the visitor's paid visits on the campaign
newsletter_same_visit AS (

    SELECT
        p.visitor_id,
        p.src_campaign,
        1 AS newsletter_signup_same_visit,
        MIN(e.event_time) AS first_newsletter_same_visit_time
    FROM paid_visits p
    JOIN events e
        ON p.visit_id = e.visit_id
        AND e.is_newsletter = 1
    GROUP BY p.visitor_id, p.src_campaign

),

-- for each converter, the one campaign whose first paid arrival is the latest before the first purchase
last_touch AS (

    SELECT
        vc.visitor_id,
        vc.src_campaign
    FROM visitor_campaign vc
    JOIN visitor_flags vf
        ON vc.visitor_id = vf.visitor_id
        AND vf.converted = 1
        AND vc.first_paid_time <= vf.first_conversion_time
    QUALIFY ROW_NUMBER() OVER (PARTITION BY vc.visitor_id ORDER BY vc.first_paid_time DESC, vc.src_campaign ASC) = 1

),

-- every paid TOF / MOF arrival, keyed by its own cookie and every paid cookie linked to it by account
upper_touches AS (

    SELECT
        visitor_id,
        funnel_stage_v2 AS stage,
        first_paid_time
    FROM visitor_campaign
    WHERE funnel_stage_v2 IN ('TOF', 'MOF')

    UNION DISTINCT

    SELECT
        i2.visitor_id,
        vc.funnel_stage_v2 AS stage,
        vc.first_paid_time
    FROM visitor_campaign vc
    JOIN identity i1 ON vc.visitor_id = i1.visitor_id
    JOIN identity i2
        ON i1.user_id = i2.user_id
        AND vc.visitor_id != i2.visitor_id
    WHERE vc.funnel_stage_v2 IN ('TOF', 'MOF')

),

prior_upper AS (

    SELECT
        vc.visitor_id,
        vc.src_campaign,
        MIN(IFF(u.stage = 'TOF', u.first_paid_time, NULL)) AS first_prior_tof_time,
        MIN(IFF(u.stage = 'MOF', u.first_paid_time, NULL)) AS first_prior_mof_time
    FROM visitor_campaign vc
    JOIN upper_touches u
        ON vc.visitor_id = u.visitor_id
        AND u.first_paid_time < vc.first_paid_time
    GROUP BY vc.visitor_id, vc.src_campaign

)

SELECT
    -- keys
    vc.visitor_id,
    vc.src_campaign,

    -- dates
    vc.first_paid_time,
    DATE(vc.first_paid_time) AS first_paid_date,
    v.first_paid_time_visitor,

    -- attributes
    vc.funnel_stage,
    vc.funnel_stage_v2,
    vc.agency,
    vc.landing_content_pillar,
    vc.ro_best_lower_bound_campaign,
    v.ro_best_lower_bound_visitor,
    vc.paid_page_views,

    -- over time (the visitor's; identical on each of their rows)
    COALESCE(vf.saw_paywall, 0) AS saw_paywall,
    COALESCE(vf.interacted, 0) AS interacted,
    COALESCE(vf.saw_offer, 0) AS saw_offer,
    COALESCE(vf.interacted_offer, 0) AS interacted_offer,
    COALESCE(vf.converted, 0) AS converted,
    COALESCE(vf.converted_browser_link_only, 0) AS converted_browser_link_only,
    COALESCE(vf.converted_via_paywall, 0) AS converted_via_paywall,
    vf.first_paywall_time,
    vf.first_interaction_time,
    vf.first_offer_time,
    vf.first_offer_interaction_time,
    vf.first_conversion_time,
    vf.first_paywall_conversion_time,
    DATEDIFF(DAY, v.first_paid_time_visitor, vf.first_conversion_time) AS days_to_conversion,
    GREATEST(COALESCE(vf.newsletter_signup, 0), COALESCE(nv.newsletter_signup_same_visit, 0)) AS newsletter_signup,
    LEAST(
        COALESCE(vf.first_newsletter_time, nv.first_newsletter_same_visit_time),
        COALESCE(nv.first_newsletter_same_visit_time, vf.first_newsletter_time)
    ) AS first_newsletter_time,
    DATEDIFF(
        DAY,
        v.first_paid_time_visitor,
        LEAST(
            COALESCE(vf.first_newsletter_time, nv.first_newsletter_same_visit_time),
            COALESCE(nv.first_newsletter_same_visit_time, vf.first_newsletter_time)
        )
    ) AS days_to_newsletter_signup,

    -- same visit (this campaign's paid page views)
    COALESCE(cf.saw_paywall_same_visit, 0) AS saw_paywall_same_visit,
    COALESCE(cf.interacted_same_visit, 0) AS interacted_same_visit,
    COALESCE(cf.saw_offer_same_visit, 0) AS saw_offer_same_visit,
    COALESCE(cf.interacted_offer_same_visit, 0) AS interacted_offer_same_visit,
    COALESCE(cf.converted_same_visit, 0) AS converted_same_visit,
    COALESCE(cf.converted_via_paywall_same_visit, 0) AS converted_via_paywall_same_visit,
    COALESCE(nv.newsletter_signup_same_visit, 0) AS newsletter_signup_same_visit,
    nv.first_newsletter_same_visit_time,

    -- last paid touch, and the upper-funnel touches before this arrival
    lt.visitor_id IS NOT NULL AS is_last_paid_touch,
    IFF(pu.first_prior_tof_time IS NOT NULL, 1, 0) AS prior_tof_touch,
    IFF(pu.first_prior_mof_time IS NOT NULL, 1, 0) AS prior_mof_touch,
    pu.first_prior_tof_time,
    pu.first_prior_mof_time,
    DATEDIFF(
        DAY,
        LEAST(
            COALESCE(pu.first_prior_tof_time, pu.first_prior_mof_time),
            COALESCE(pu.first_prior_mof_time, pu.first_prior_tof_time)
        ),
        vc.first_paid_time
    ) AS days_since_upper_touch
FROM visitor_campaign vc
JOIN visitor v ON vc.visitor_id = v.visitor_id
LEFT JOIN visitor_flags vf ON vc.visitor_id = vf.visitor_id
LEFT JOIN campaign_flags cf
    ON vc.visitor_id = cf.visitor_id
    AND vc.src_campaign = cf.src_campaign
LEFT JOIN newsletter_same_visit nv
    ON vc.visitor_id = nv.visitor_id
    AND vc.src_campaign = nv.src_campaign
LEFT JOIN last_touch lt
    ON vc.visitor_id = lt.visitor_id
    AND vc.src_campaign = lt.src_campaign
LEFT JOIN prior_upper pu
    ON vc.visitor_id = pu.visitor_id
    AND vc.src_campaign = pu.src_campaign
