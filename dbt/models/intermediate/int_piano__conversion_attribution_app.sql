{{ config(
    materialized="view",
    tags=["piano", "intermediate"]
) }}

WITH consolidated_conversions AS (

    SELECT
        *,
        'Mobile App' AS app_type
    FROM {{ ref('int_piano__offsite_conversion_event_consolidation') }}

),

app_experiences AS (

    SELECT
        experience_id,
        experience_name
    FROM {{ ref('dim_experience') }}
    WHERE app_type = 'Mobile App'

),

lead_up_ctas AS (

    SELECT
        c.*,
        e.event_name,
        e.event_time,
        e.experience_id,
        e.card_id,
        e.card_action,
        e.template_id,
        e.ab_test_variant_name
    FROM consolidated_conversions c
    LEFT JOIN {{ ref('stg_piano__composer_events') }} e
        ON e.visit_id = c.visit_id
        AND e.event_time <= c.conversion_time
        AND e.event_name IN ('experience.action', 'experience.interaction', 'subscription.select')
        -- AND e.page != 'subscription.app.native.gate.page'  -- Just use Piano gate for experience properties.
        AND e.template_id != 'OTA89Y3WW201'  -- Exclude privacy policy
    ORDER BY c.conversion_id, e.event_time

),

fill_forward_ids AS (

    SELECT
        * EXCLUDE (experience_id, template_id, ab_test_variant_name),
        COALESCE(
            LAST_VALUE(experience_id IGNORE NULLS) OVER (PARTITION BY visitor_id ORDER BY event_time),
            'EX0000000000'
        ) AS experience_id,
        COALESCE(
            LAST_VALUE(template_id IGNORE NULLS) OVER (PARTITION BY visitor_id ORDER BY event_time),
            'OT0000000000'
        ) AS template_id,
        LAST_VALUE(ab_test_variant_name IGNORE NULLS) OVER (PARTITION BY visitor_id ORDER BY event_time) AS ab_test_variant_name
    FROM lead_up_ctas

),

-- This step is to fix specific known issue where the wrong experience_id or template_id was associated with certain conversions,
-- likely due to a bug in the event tracking or data processing. We are hardcoding the correct mappings for these specific cases
-- based on historical data and analysis.
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

)

SELECT
    conversion_id,
    subscription_id,
    visitor_id,
    user_id,
    user_first_party_id,
    visit_id,
    visit_time,
    device_type,
    app_type,
    os_group,
    conversion_time,
    conversion_time::DATE AS conversion_date,
    term_id,
    term_name,
    term_offer_id,
    term_offer_name,
    billing_period,
    NULL AS vx_promo_code,
    CASE
        -- United States
        WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 month' AND LOWER(term_name) ILIKE '%ios%' THEN 8.99 * 0.7  -- Assuming 30% app store fee for iOS
        WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 year' AND LOWER(term_name) ILIKE '%ios%' THEN 49.99 * 0.7  -- Assuming 30% app store fee for iOS
        WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 month' AND LOWER(term_name) ILIKE '%android%' THEN 8.99 * 0.85  -- Assuming 15% app store fee for Android
        WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 year' AND LOWER(term_name) ILIKE '%android%' THEN 49.99 * 0.85  -- Assuming 15% app store fee for Android
        WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 month' AND LOWER(os_group) IN ('ios', 'ipados', 'macos') THEN 8.99 * 0.7  -- Assuming 30% app store fee for iOS
        WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 year' AND LOWER(os_group) IN ('ios', 'ipados', 'macos') THEN 49.99 * 0.7  -- Assuming 30% app store fee for iOS
        WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 month' AND LOWER(os_group) IN ('android', 'chrome os', 'windows') THEN 8.99 * 0.85  -- Assuming 15% app store fee for Android
        WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 year' AND LOWER(os_group) IN ('android', 'chrome os', 'windows') THEN 49.99 * 0.85  -- Assuming 15% app store fee for Android

        -- Canada
        WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 month' AND LOWER(term_name) ILIKE '%ios%' THEN 9.1622 * 0.7  -- Assuming 30% app store fee for iOS
        WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 year' AND LOWER(term_name) ILIKE '%ios%' THEN 49.3659 * 0.7  -- Assuming 30% app store fee for iOS
        WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 month' AND LOWER(term_name) ILIKE '%android%' THEN 9.1622 * 0.85  -- Assuming 15% app store fee for Android
        WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 year' AND LOWER(term_name) ILIKE '%android%' THEN 49.3659 * 0.85  -- Assuming 15% app store fee for Android
        WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 month' AND LOWER(os_group) IN ('ios', 'ipados', 'macos') THEN 9.1622 * 0.7  -- Assuming 30% app store fee for iOS
        WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 year' AND LOWER(os_group) IN ('ios', 'ipados', 'macos') THEN 49.3659 * 0.7  -- Assuming 30% app store fee for iOS
        WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 month' AND LOWER(os_group) IN ('android', 'chrome os', 'windows') THEN 9.1622 * 0.85  -- Assuming 15% app store fee for Android
        WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 year' AND LOWER(os_group) IN ('android', 'chrome os', 'windows') THEN 49.3659 * 0.85  -- Assuming 15% app store fee for Android
        ELSE NULL
    END AS cart_turnovertaxfree,
    subscription_period_number,
    COALESCE(created_via_upgrade, FALSE) AS created_via_upgrade,
    src,
    src_detail,
    geo_id,
    geo_country,
    geo_region,
    geo_city,
    TO_VARCHAR(conversion_time, 'YYYY-MM') AS cohort_month,
    experience_id,
    card_id,
    card_action,
    template_id,
    ab_test_variant_name,
    NULL AS c1x_lts,
    NULL AS c1x_content_likely_to_convert,
    NULL AS c1x_likelihood_to_register,
    NULL AS c1x_likelihood_to_return,
    NULL AS c1x_revenue_auto_optimization
FROM fill_forward_ids
QUALIFY ROW_NUMBER() OVER (PARTITION BY conversion_id ORDER BY event_time DESC) = 1
