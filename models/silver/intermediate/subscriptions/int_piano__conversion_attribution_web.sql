{{ config(
    materialized="view",
    tags=["piano", "intermediate"]
) }}

WITH web_conversion_events AS (

    SELECT *
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        site_id = 638824
        AND event_time::DATE > '2025-06-25'
        AND event_name IN ('vx.conversion', 'vx.conversion.optout')
        AND term_offer_id IN ('OFR1N7V2XJPI',  -- Initial Offer (USA)
                              'OFC29VO25AKU',  -- Initial Offer (Canada)
                              'OFNG74GEQIKA',  -- ACP Upgrade for Annual Plan (USA)
                              'OFR18ARIK45H',  -- ACP Upgrade for Monthly Plan (USA)
                              'OF9Z5HTBLJ7O',  -- ACP Upgrade for Annual Plan (Canada)
                              'OFHRCL9PQBXN')  -- ACP Upgrade for Monthly Plan (Canada)
        -- AND NOT created_via_upgrade

),

-- Gets all page view, CTA and interaction events leading up to conversion (previous day)
lead_up_events AS (

    SELECT
        e.* EXCLUDE (conversion_id),
        c.conversion_id,
        c.event_time AS conversion_time,
        ROW_NUMBER() OVER (
            PARTITION BY c.conversion_id, e.event_name
            ORDER BY e.event_time DESC
        ) AS rn
    FROM {{ ref('int_piano__events_cleaned') }} e
    INNER JOIN web_conversion_events c
        ON c.visitor_id = e.visitor_id
        AND e.event_time < c.event_time  -- Strictly before conversion
        AND e.event_time >= DATEADD(DAY, -1, c.event_time)
    WHERE 1=1
        AND e.site_id = 638824
        AND e.event_time::DATE > '2025-06-25'
        AND e.event_name IN ('experience.action', 'experience.interaction', 'subscription.select')
        AND (e.page NOT IN ('id.auth_identifier_signin.page',
                            'id.auth_identifier_magic_link_check.page',
                            'id.auth_identifier_signin_password.page')
             OR e.page IS NULL)
        AND e.event_url != 'https://www.bbc.com/subscribe'

),

-- Joins the conversion event on the last CTA, interaction and page view
joined AS (

    SELECT
        -- vx.conversion-specific properties
        c.conversion_id,
        c.subscription_id,
        c.visitor_id,
        c.user_id,
        c.user_first_party_id,
        c.visit_id,
        c.visit_time,
        c.event_time AS conversion_time,
        c.event_time::DATE AS conversion_date,
        c.device_type_id,
        c.os_group_id,
        c.term_id,
        c.term_name,
        c.term_offer_id,
        c.term_offer_name,
        c.billing_period,
        c.vx_promo_code,
        c.cart_turnovertaxfree,
        c.subscription_period_number,
        COALESCE(c.created_via_upgrade, FALSE) AS created_via_upgrade,
        c.src,
        c.src_detail,
        c.geo_id,
        c.geo_country,
        c.geo_region,
        c.geo_city,

        -- vx.conversion shared properties
        c.experience_id AS conversion_experience_id,
        c.card_id AS conversion_card_id,
        c.card_action AS conversion_card_action,
        c.template_id AS conversion_template_id,
        c.ab_test_variant_name AS conversion_ab_test_variant_name,
        c.c1x_lts AS conversion_c1x_lts,
        c.c1x_content_likely_to_convert AS conversion_c1x_content_likely_to_convert,
        c.c1x_likelihood_to_register AS conversion_c1x_likelihood_to_register,
        c.c1x_likelihood_to_return AS conversion_c1x_likelihood_to_return,
        c.c1x_revenue_auto_optimization AS conversion_c1x_revenue_auto_optimization,

        -- last experience.action relevant properties
        a.experience_id AS action_experience_id,
        a.card_id AS action_card_id,
        a.card_action AS action_card_action,
        a.template_id AS action_template_id,
        a.ab_test_variant_name AS action_ab_test_variant_name,
        a.c1x_lts AS action_c1x_lts,
        a.c1x_content_likely_to_convert AS action_c1x_content_likely_to_convert,
        a.c1x_likelihood_to_register AS action_c1x_likelihood_to_register,
        a.c1x_likelihood_to_return AS action_c1x_likelihood_to_return,
        a.c1x_revenue_auto_optimization AS action_c1x_revenue_auto_optimization,

        -- last experience.interaction relevant properties
        i.experience_id AS interaction_experience_id,
        i.card_id AS interaction_card_id,
        i.card_action AS interaction_card_action,
        i.template_id AS interaction_template_id,
        i.ab_test_variant_name AS interaction_ab_test_variant_name,
        i.c1x_lts AS interaction_c1x_lts,
        i.c1x_content_likely_to_convert AS interaction_c1x_content_likely_to_convert,
        i.c1x_likelihood_to_register AS interaction_c1x_likelihood_to_register,
        i.c1x_likelihood_to_return AS interaction_c1x_likelihood_to_return,
        i.c1x_revenue_auto_optimization AS interaction_c1x_revenue_auto_optimization,

        -- subscribe.select event tells us if they click the subscribe button
        IFF(s.event_time IS NOT NULL, TRUE, FALSE) AS clicked_subscribe

    FROM web_conversion_events c

    LEFT JOIN (SELECT *
               FROM lead_up_events
               WHERE event_name = 'experience.action' AND rn=1) a
        ON a.conversion_id = c.conversion_id

    LEFT JOIN (SELECT *
               FROM lead_up_events
               WHERE event_name = 'experience.interaction' AND rn=1) i
        ON i.conversion_id = c.conversion_id

    -- See if there was a subscription.select in build up to conversion
    LEFT JOIN (SELECT *
               FROM lead_up_events
               WHERE event_name = 'subscription.select' AND rn=1) s
        ON s.conversion_id = c.conversion_id
        AND s.event_time BETWEEN DATEADD(HOUR, -1, c.event_time) AND c.event_time

),

attribution AS (

    SELECT
        conversion_id,
        subscription_id,
        visitor_id,
        user_id,
        user_first_party_id,
        visit_id,
        visit_time,
        MD5('Web') AS app_type_id,
        device_type_id,
        os_group_id,
        conversion_time,
        conversion_date,
        term_id,
        term_name,
        term_offer_id,
        term_offer_name,
        billing_period,
        vx_promo_code,
        cart_turnovertaxfree,
        subscription_period_number,
        created_via_upgrade,
        src,
        src_detail,
        geo_id,
        geo_country,
        geo_region,
        geo_city,
        TO_VARCHAR(conversion_time, 'YYYY-MM') AS cohort_month,

        -- If conversion is Landing Page and they clicked subscribe in build up, assume it's the Landing Page
        -- Else coalesce Interactions (for paywalls) and Actions (for ribbons) and Conversions (usually just LP standalone conversions)
        CASE
            WHEN conversion_experience_id = 'EX843FEP7H0N' AND clicked_subscribe THEN 'EX843FEP7H0N'
            ELSE COALESCE(interaction_experience_id, action_experience_id, 'EX843FEP7H0N')
        END AS experience_id,

        CASE
            WHEN conversion_experience_id = 'EX843FEP7H0N' AND clicked_subscribe THEN 'showOfferU1L6WTFCILCB9'
            ELSE COALESCE(interaction_card_id, action_card_id, 'showOfferU1L6WTFCILCB9')
        END AS card_id,

        CASE
            WHEN conversion_experience_id = 'EX843FEP7H0N' AND clicked_subscribe THEN 'showOffer'
            ELSE COALESCE(interaction_card_action, action_card_action, 'showOffer')
        END AS card_action,

        CASE
            WHEN conversion_experience_id = 'EX843FEP7H0N' AND clicked_subscribe THEN 'OTSEA34UH0YZ'
            ELSE COALESCE(interaction_template_id, action_template_id, 'OTSEA34UH0YZ')
        END AS template_id,

        COALESCE(conversion_ab_test_variant_name, interaction_ab_test_variant_name, action_ab_test_variant_name) AS ab_test_variant_name,
        COALESCE(conversion_c1x_lts, interaction_c1x_lts, action_c1x_lts) AS c1x_lts,
        COALESCE(conversion_c1x_content_likely_to_convert, interaction_c1x_content_likely_to_convert, action_c1x_content_likely_to_convert) AS c1x_content_likely_to_convert,
        COALESCE(conversion_c1x_likelihood_to_register, interaction_c1x_likelihood_to_register, action_c1x_likelihood_to_register) AS c1x_likelihood_to_register,
        COALESCE(conversion_c1x_likelihood_to_return, interaction_c1x_likelihood_to_return, action_c1x_likelihood_to_return) AS c1x_likelihood_to_return,
        COALESCE(conversion_c1x_revenue_auto_optimization, interaction_c1x_revenue_auto_optimization, action_c1x_revenue_auto_optimization) AS c1x_revenue_auto_optimization

    FROM joined

)

SELECT *
FROM attribution
