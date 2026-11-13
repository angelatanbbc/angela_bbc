{{
    config(
        materialized="table",
        tags=["marketing", "tableau"]
    )
}}

SELECT
    -- grain
    HEX_ENCODE(visitor_id)::VARCHAR(64) AS visitor_id,
    LEFT(src_campaign, 512)::VARCHAR(512) AS src_campaign,
    LEFT(funnel_stage, 3)::VARCHAR(3) AS funnel_stage,
    LEFT(funnel_stage_v2, 16)::VARCHAR(16) AS funnel_stage_v2,
    LEFT(agency, 16)::VARCHAR(16) AS src_bbc_team,
    LEFT(landing_content_pillar, 512)::VARCHAR(512) AS landing_content_pillar,

    -- cohort
    first_paid_time,
    first_paid_date,
    first_paid_date AS date_day,
    first_paid_time_visitor,
    paid_page_views,

    -- RevOps and LTS
    ro_best_lower_bound_campaign,
    ro_best_lower_bound_visitor,
    ro_first_lower_bound_visitor,
    CASE
        WHEN ro_best_lower_bound_visitor >= {{ var('high_ro_threshold') }}
            THEN 'RevOps {{ var("high_ro_threshold") }}+'
        WHEN ro_best_lower_bound_visitor >= {{ var('med_ro_threshold') }}
            THEN 'RevOps {{ var("med_ro_threshold") }}-{{ var("high_ro_threshold") - 1 }}'
        ELSE 'other'
    END::VARCHAR(16) AS revops_band,
    lts_best_lower_bound_campaign,
    lts_best_lower_bound_visitor,
    lts_first_lower_bound_visitor,
    {{ lts_band('lts_best_lower_bound_visitor') }}::VARCHAR(16) AS lts_band,

    -- over time (the visitor's)
    saw_paywall,
    interacted,
    saw_offer,
    interacted_offer,
    converted,
    converted_browser_link_only,
    converted_via_paywall,
    first_paywall_time,
    first_interaction_time,
    first_offer_time,
    first_offer_interaction_time,
    first_conversion_time,
    first_paywall_conversion_time,
    days_to_conversion,
    newsletter_signup,
    first_newsletter_time,
    days_to_newsletter_signup,

    -- same visit (this campaign's paid page views)
    saw_paywall_same_visit,
    interacted_same_visit,
    saw_offer_same_visit,
    interacted_offer_same_visit,
    converted_same_visit,
    converted_via_paywall_same_visit,
    newsletter_signup_same_visit,
    first_newsletter_same_visit_time,

    -- last paid touch and earlier upper-funnel touches
    is_last_paid_touch,
    prior_tof_touch,
    prior_mof_touch,
    first_prior_tof_time,
    first_prior_mof_time,
    days_since_upper_touch
FROM {{ ref('fct_paid_visitor_funnel') }}
