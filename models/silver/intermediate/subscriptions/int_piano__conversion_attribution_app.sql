{{ config(
    materialized="view",
    tags=["piano", "intermediate"]
) }}

WITH consolidated_conversions AS (

    SELECT *
    FROM {{ ref('int_piano__offsite_conversion_event_consolidation') }}

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
    LEFT JOIN {{ ref('int_piano__events_cleaned') }} e
        ON e.visit_id = c.visit_id
        AND e.site_id = 638824
        AND e.event_time::DATE > '2025-06-25'
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

),

list_prices AS (

    -- App store list prices by offer and billing period
    SELECT
        *,
        CASE
            -- United States
            WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 month' THEN 8.99
            WHEN term_offer_id = 'OFR1N7V2XJPI' AND billing_period = '1 year' THEN 49.99
            -- Canada
            WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 month' THEN 9.1622
            WHEN term_offer_id = 'OFC29VO25AKU' AND billing_period = '1 year' THEN 49.3659
        END AS app_store_list_price
    FROM last_fix

)

SELECT
    conversion_id,
    subscription_id,
    visitor_id,
    user_id,
    user_first_party_id,
    visit_id,
    visit_time,
    device_platform_id,
    conversion_time,
    conversion_time::DATE AS conversion_date,
    term_id,
    term_name,
    term_offer_id,
    term_offer_name,
    billing_period,
    payment_provider,
    NULL AS vx_promo_code,
    -- App store conversions carry no value, so revenue is the list price less
    -- the store's fee, keyed on where the subscription is billed. Stripe and
    -- Braintree checkouts that Piano reports offsite carry the charge Piano
    -- recorded and pay no store fee.
    CASE payment_provider
        WHEN 'Apple App Store' THEN app_store_list_price * 0.7  -- Assuming 30% Apple App Store fee
        WHEN 'Google Play' THEN app_store_list_price * 0.85  -- Assuming 15% Google Play fee
        ELSE cart_turnovertaxfree
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
FROM list_prices
QUALIFY ROW_NUMBER() OVER (PARTITION BY conversion_id ORDER BY event_time DESC) = 1
