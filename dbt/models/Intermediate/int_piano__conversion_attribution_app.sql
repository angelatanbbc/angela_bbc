{{ config(materialized="table") }}

WITH converted_visitors AS (

    SELECT
        visitor_id,
        visit_id,
        event_time AS conversion_time
    FROM {{ ref('stg_piano__subs_events_app') }}
    WHERE event_name = 'vx.conversion'

),

app_experiences AS (

    SELECT *
    FROM {{ ref('app_experiences') }}
),

app_templates AS (

    SELECT *
    FROM {{ ref('app_templates') }}
),

lead_up_ctas AS (

    SELECT
        e.*,
        c.conversion_time
    FROM {{ ref('stg_piano__subs_events_app') }} e
    JOIN converted_visitors c
        ON e.visitor_id = c.visitor_id
        AND e.visit_id = c.visit_id
        AND e.event_name IN ('vx.conversion', 'experience.action', 'experience.interaction')
    ORDER BY e.visitor_id, event_time

),

fill_forward_ids AS (

    SELECT
        * EXCLUDE (experience_id, experience_name, template_id, template_name, ab_test_variant_name),
        COALESCE(LAST_VALUE(experience_id) IGNORE NULLS OVER (PARTITION BY visitor_id ORDER BY event_time), 'EX0000000000') AS experience_id,
        COALESCE(LAST_VALUE(template_id) IGNORE NULLS OVER (PARTITION BY visitor_id ORDER BY event_time), 'OT0000000000') AS template_id,
        LAST_VALUE(ab_test_variant_name) IGNORE NULLS OVER (PARTITION BY visitor_id ORDER BY event_time) AS ab_test_variant_name
    FROM lead_up_ctas

),

last_fix AS (

    SELECT
        * EXCLUDE (experience_id, template_id),
        CASE experience_id
            WHEN 'EXOW41VZU9HJ' THEN 'EXGKIRY8NX6A'
            WHEN 'EXEXRY1Q84OY' THEN 'EX6LXHDUVZLO'
            ELSE experience_id
        END AS experience_id,
        CASE template_id
            WHEN 'OT4Q15OHD49Y' THEN 'OT29Y8NINZH1'
            WHEN 'OTUZIZ38D800' THEN 'OTDZOQ30X0SN'
            ELSE template_id
        END AS template_id
    FROM fill_forward_ids

),

named AS (
    
    SELECT
        f.*,
        IFNULL(e.experience_name, 'Unknown Experience') AS experience_name,
        IFNULL(t.template_name, 'Unknown Template') AS template_name
    FROM last_fix f
    LEFT JOIN app_experiences e
        ON f.experience_id = e.experience_id
    LEFT JOIN app_templates t
        ON f.template_id = t.template_id

)

SELECT
    -- Generated IDs because these are not coming through right now
    {{ dbt_utils.generate_surrogate_key(['visitor_id', 'conversion_time']) }} AS conversion_id,
    {{ dbt_utils.generate_surrogate_key(['visitor_id', 'visit_id', 'conversion_time']) }} AS subscription_id,
    visitor_id,
    user_id,
    visit_id,
    visit_time,
    app_type,
    os_group,
    conversion_time,
    term_id,
    term_name,
    term_offer_id,
    term_offer_name,
    billing_period,
    vx_promo_code,
    cart_turnovertaxfree,
    subscription_period_number,
    src,
    src_detail,
    geo_id,
    geo_country,
    geo_region,
    geo_city,
    TO_VARCHAR(conversion_time, 'YYYY-MM') AS cohort_month,
    experience_id,
    experience_name,
    card_id,
    card_name,
    card_action,
    template_id,
    template_name,
    ab_test_variant_name,
    NULL AS c1x_lts,
    NULL AS c1x_content_likely_to_convert,
    NULL AS c1x_likelihood_to_register,
    NULL AS c1x_likelihood_to_return,
    NULL AS c1x_revenue_auto_optimization
FROM named
WHERE event_name = 'vx.conversion'
