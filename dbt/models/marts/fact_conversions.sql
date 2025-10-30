{{
    config(
        materialized="incremental",
        unique_key='subscription_id',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

WITH conversion_events AS (

    SELECT
        subscription_id,
        visitor_id,
        visit_id,
        user_id,
        visit_time,
        device_type,
        event_time AS conversion_time,
        billing_period,
        vx_promo_code,
        page,
        event_url,
        experience_name,
        template_name,
        ab_test_variant_name,
        c1x_lts
    FROM {{ ref('stg_piano_events__conversions') }}
    WHERE 1=1
    {% if is_incremental() %}
        AND event_time >= DATEADD(DAY, -1, (SELECT MAX(conversion_time) FROM {{ this }}))
    {% endif %}

),

-- Gets all page view, CTA and interaction events leading up to conversion (previous day)
lead_up_events AS (

    SELECT
        e.*,
        c.conversion_time,
        ROW_NUMBER() OVER (
            PARTITION BY e.visitor_id, e.event_name, c.conversion_time
            ORDER BY event_time DESC
        ) AS rn
    FROM {{ ref('stg_piano_events__exposures') }} e
    INNER JOIN conversion_events c
        ON c.visitor_id = e.visitor_id
        AND e.event_time < c.conversion_time  -- Strictly before conversion
        AND e.event_time >= DATEADD(DAY, -1, c.conversion_time)
    WHERE 1=1
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
        c.subscription_id,
        c.visitor_id,
        c.user_id,
        c.visit_id,
        c.visit_time,
        c.device_type,
        c.conversion_time,
        c.billing_period,
        c.vx_promo_code,

        -- vx.conversion shared properties
        c.experience_name AS conversion_experience_name,
        c.template_name AS conversion_template_name,
        c.ab_test_variant_name AS conversion_ab_test_variant_name,
        c.c1x_lts AS conversion_c1x_lts,

        -- last experience.action relevant properties
        a.experience_name AS action_experience_name,
        a.template_name AS action_template_name,
        a.ab_test_variant_name AS action_ab_test_variant_name,
        a.c1x_lts AS action_c1x_lts,
        
        -- last experience.interaction relevant properties
        i.experience_name AS interaction_experience_name,
        i.template_name AS interaction_template_name,
        i.ab_test_variant_name AS interaction_ab_test_variant_name,
        i.c1x_lts AS interaction_c1x_lts,

        -- subscribe.select event tells us if they click the subscribe button
        IFF(s.event_time IS NOT NULL, TRUE, FALSE) AS clicked_subscribe

    FROM conversion_events c

    LEFT JOIN (SELECT *
               FROM lead_up_events
               WHERE event_name = 'experience.action' AND rn=1) a
        ON a.visitor_id = c.visitor_id
        AND a.conversion_time = c.conversion_time

    LEFT JOIN (SELECT *
               FROM lead_up_events
               WHERE event_name = 'experience.interaction' AND rn=1) i
        ON i.visitor_id = c.visitor_id
        AND i.conversion_time = c.conversion_time

    -- See if there was a subscription.select in build up to conversion
    LEFT JOIN (SELECT *
               FROM lead_up_events
               WHERE event_name = 'subscription.select' AND rn=1) s
        ON s.visitor_id = c.visitor_id
        AND s.event_time BETWEEN DATEADD(HOUR, -1, c.conversion_time) AND c.conversion_time
        
),

attribution AS (

    SELECT
        subscription_id,
        visitor_id,
        user_id,
        visit_id,
        visit_time,
        COALESCE(device_type, 'Unknown') AS device_type,
        conversion_time,
        COALESCE(billing_period, 'Unknown') AS billing_period,
        COALESCE(vx_promo_code, 'None') AS vx_promo_code,

        -- If conversion is Landing Page and they clicked subscribe in build up, assume it's the Landing Page
        -- Else coalesce Interactions (for paywalls) and Actions (for ribbons) and Conversions (usually just LP standalone conversions)
        CASE
            WHEN conversion_experience_name = '003 - Subscription Landing Page' AND clicked_subscribe THEN '003 - Subscription Landing Page'
            ELSE COALESCE(interaction_experience_name, action_experience_name, '003 - Subscription Landing Page')
        END AS experience_name,
        
        CASE
            WHEN conversion_experience_name = '003 - Subscription Landing Page' AND clicked_subscribe THEN 'Subscription Landing Page'
            ELSE COALESCE(interaction_template_name, action_template_name, 'Subscription Landing Page')
        END AS template_name,

        COALESCE(action_ab_test_variant_name, 'None') AS ab_test_variant_name,
        COALESCE(conversion_c1x_lts, interaction_c1x_lts, action_c1x_lts, 'Unknown') AS c1x_lts
    FROM joined

)

SELECT *
FROM attribution
