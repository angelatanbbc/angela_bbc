{{ config(
    materialized="view",
    tags=["piano", "intermediate"]
) }}

-- Get offsite conversions. Most are billed by an app store (external_api_source),
-- but Piano also reports some Stripe checkouts made from the app as offsite
-- (payment_provider); those carry the charge in cart_turnovertaxfree.
WITH offsite_conversions AS (

    SELECT
        conversion_id,
        subscription_id,
        event_time AS conversion_time,
        user_id,
        user_first_party_id,
        term_id,
        term_name,
        -- COALESCE(term_offer_id, 'OFR1N7V2XJPI') AS term_offer_id,
        -- COALESCE(term_offer_name, 'BBC Subscription') AS term_offer_name,
        IFF(term_name ILIKE '%monthly%', '1 month', '1 year') AS billing_period,
        COALESCE(
            CASE external_api_source
                WHEN 'APPLE_ITUNES' THEN 'Apple App Store'
                WHEN 'GOOGLE_PLAY' THEN 'Google Play'
            END,
            payment_provider
        ) AS payment_provider,
        cart_turnovertaxfree,
        subscription_period_number,
        created_via_upgrade
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        site_id = 638824
        AND event_time::DATE > '2025-06-25'
        AND event_name = 'vx.conversion.offsite'
        AND subscription_id IS NOT NULL  -- Excludes group grants such as the Ad Sales group subscription

),

-- Get onsite conversion events for mobile app experiences
onsite_conversions AS (

    SELECT
        event_time AS conversion_time,
        user_first_party_id,
        visitor_id,
        visit_id,
        visit_time,
        device_type,
        os_group,
        src,
        src_detail,
        geo_id,
        geo_country,
        geo_region,
        geo_city
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        site_id = 638824
        AND event_time::DATE > '2025-06-25'
        AND event_name = 'vx.conversion'
        AND subscription_id IS NULL  -- Selects only mobile app conversions

),

-- Match each offsite conversion to the same user's nearest onsite conversion. Matching on
-- time alone gave conversions another user's visit when the user's own event was missing.
-- Conversions with no match (no in-app event, or a web upgrade Piano reports offsite) are
-- kept with no visit, visitor or geo.
ranked_matches AS (

    SELECT
        ofs.*,
        ons.* EXCLUDE (conversion_time, user_first_party_id),
        ROW_NUMBER() OVER (
            PARTITION BY ofs.conversion_id
            ORDER BY ABS(DATEDIFF(SECOND, ofs.conversion_time, ons.conversion_time))
        ) AS ranking
    FROM offsite_conversions ofs
    LEFT JOIN onsite_conversions ons
        ON ofs.user_first_party_id = ons.user_first_party_id
        AND ABS(DATEDIFF(HOUR, ofs.conversion_time, ons.conversion_time)) <= 1  -- window in hours

)

SELECT
    conversion_id,
    subscription_id,
    visitor_id,
    user_id,
    user_first_party_id,
    visit_id,
    visit_time,
    -- Without a matched event, the store still tells us the OS
    {{ generate_device_platform_id(
        "'Mobile App'",
        'device_type',
        "COALESCE(os_group, CASE payment_provider WHEN 'Apple App Store' THEN 'iOS' WHEN 'Google Play' THEN 'Android' END)"
    ) }} AS device_platform_id,
    conversion_time,
    term_id,
    term_name,
    CASE geo_country
        WHEN 'Canada' THEN 'OFC29VO25AKU'
        ELSE 'OFR1N7V2XJPI'  -- Assume United States
    END AS term_offer_id,
    'BBC Subscription' AS term_offer_name,
    billing_period,
    payment_provider,
    cart_turnovertaxfree,
    subscription_period_number,
    created_via_upgrade,
    src,
    src_detail,
    -- Unmatched conversions have no geo, so they get the Unknown geography
    COALESCE(geo_id, {{ generate_geo_id('geo_country', 'geo_region') }}) AS geo_id,
    COALESCE(geo_country, 'Unknown') AS geo_country,
    COALESCE(geo_region, 'Unknown') AS geo_region,
    geo_city
FROM ranked_matches
WHERE ranking = 1
