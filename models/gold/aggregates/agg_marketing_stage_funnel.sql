{{
    config(
        materialized="table",
        tags=["marketing"]
    )
}}

/*
The paid visitor funnel by stage, counted as the Marketing Measurement Dashboard's Funnel tab counts it: one
row per paid visitor and funnel stage (TOF, MOF, BOF, BOF (Docs)), dated on the visitor's first day in that
stage, plus one row per visitor for 'All stages', dated on their first paid day. A flag is 1 when any of the
visitor's campaigns in the stage has it. Feeds the visitor funnel in sv_marketing.
*/

WITH paid AS (

    SELECT
        visitor_id,
        funnel_stage_v2,
        src_bbc_team,
        landing_content_pillar,
        first_paid_time,
        date_day,
        lts_first_lower_bound_visitor,
        ro_first_lower_bound_visitor,
        lts_best_lower_bound_visitor,
        ro_best_lower_bound_visitor,
        days_to_conversion,
        saw_paywall,
        interacted,
        saw_offer,
        interacted_offer,
        converted,
        converted_via_paywall,
        newsletter_signup,
        saw_paywall_same_visit,
        interacted_same_visit,
        saw_offer_same_visit,
        interacted_offer_same_visit,
        converted_same_visit,
        converted_via_paywall_same_visit,
        newsletter_signup_same_visit
    FROM {{ ref('agg_marketing_visitor_funnel') }}
    WHERE funnel_stage_v2 IN ('TOF', 'MOF', 'BOF', 'BOF (Docs)')

),

-- each visitor once per stage, and once across all four stages
visitor_stages AS (

    SELECT
        IFF(GROUPING(funnel_stage_v2) = 1, 'All stages', funnel_stage_v2) AS funnel_stage,
        visitor_id,
        MIN(date_day) AS date_day,
        MIN_BY(src_bbc_team, first_paid_time) AS src_bbc_team,
        MIN_BY(landing_content_pillar, first_paid_time) AS landing_content_pillar,
        -- the scores are the visitor's, the same on each of their rows
        ANY_VALUE(lts_first_lower_bound_visitor) AS lts_first_lower_bound_visitor,
        ANY_VALUE(ro_first_lower_bound_visitor) AS ro_first_lower_bound_visitor,
        ANY_VALUE(lts_best_lower_bound_visitor) AS lts_best_lower_bound_visitor,
        ANY_VALUE(ro_best_lower_bound_visitor) AS ro_best_lower_bound_visitor,
        MIN(IFF(converted = 1, days_to_conversion, NULL)) AS days_to_conversion,
        MAX(saw_paywall) AS saw_paywall,
        MAX(interacted) AS interacted,
        MAX(saw_offer) AS saw_offer,
        MAX(interacted_offer) AS interacted_offer,
        MAX(converted) AS converted,
        MAX(converted_via_paywall) AS converted_via_paywall,
        MAX(newsletter_signup) AS newsletter_signup,
        MAX(saw_paywall_same_visit) AS saw_paywall_same_visit,
        MAX(interacted_same_visit) AS interacted_same_visit,
        MAX(saw_offer_same_visit) AS saw_offer_same_visit,
        MAX(interacted_offer_same_visit) AS interacted_offer_same_visit,
        MAX(converted_same_visit) AS converted_same_visit,
        MAX(converted_via_paywall_same_visit) AS converted_via_paywall_same_visit,
        MAX(newsletter_signup_same_visit) AS newsletter_signup_same_visit
    FROM paid
    GROUP BY GROUPING SETS ((visitor_id, funnel_stage_v2), (visitor_id))

)

SELECT
    -- grain
    LEFT(funnel_stage, 16)::VARCHAR(16) AS funnel_stage,
    visitor_id,

    -- dates
    date_day,

    -- attributes
    src_bbc_team,
    landing_content_pillar,
    lts_first_lower_bound_visitor,
    ro_first_lower_bound_visitor,
    {{ lts_band('lts_first_lower_bound_visitor') }}::VARCHAR(16) AS lts_band_on_arrival,
    CASE
        WHEN ro_first_lower_bound_visitor >= 90 THEN 'RevOps 90+'
        WHEN ro_first_lower_bound_visitor >= 80 THEN 'RevOps 80-89'
        WHEN ro_first_lower_bound_visitor >= 50 THEN 'RevOps 50-79'
        WHEN ro_first_lower_bound_visitor >= 0 THEN 'RevOps under 50'
        ELSE 'No score'
    END::VARCHAR(16) AS revops_band_on_arrival,
    {{ lts_band('lts_best_lower_bound_visitor') }}::VARCHAR(16) AS lts_band_best,
    CASE
        WHEN ro_best_lower_bound_visitor >= 90 THEN 'RevOps 90+'
        WHEN ro_best_lower_bound_visitor >= 80 THEN 'RevOps 80-89'
        WHEN ro_best_lower_bound_visitor >= 50 THEN 'RevOps 50-79'
        WHEN ro_best_lower_bound_visitor >= 0 THEN 'RevOps under 50'
        ELSE 'No score'
    END::VARCHAR(16) AS revops_band_best,

    -- outcomes over time (any later visit)
    days_to_conversion,
    saw_paywall,
    interacted,
    saw_offer,
    interacted_offer,
    converted,
    converted_via_paywall,
    newsletter_signup,

    -- outcomes in the same visit
    saw_paywall_same_visit,
    interacted_same_visit,
    saw_offer_same_visit,
    interacted_offer_same_visit,
    converted_same_visit,
    converted_via_paywall_same_visit,
    newsletter_signup_same_visit
FROM visitor_stages
