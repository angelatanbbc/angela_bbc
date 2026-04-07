{{ config(
    materialized="view",
    tags=["piano", "intermediate"]
) }}

WITH offsite_conversions AS (

    SELECT
        conversion_id,
        subscription_id,
        event_time AS conversion_time,
        user_id,
        term_id,
        term_name,
        COALESCE(term_offer_id, 'OFR1N7V2XJPI') AS term_offer_id,
        COALESCE(term_offer_name, 'BBC Subscription') AS term_offer_name,
        IFF(term_name ILIKE '%monthly%', '1 month', '1 year') AS billing_period,
        subscription_period_number
    FROM {{ ref('stg_piano__offsite_events') }}
    WHERE event_name = 'vx.conversion.offsite'

),

onsite_conversions AS (

    SELECT
        event_time AS conversion_time,
        visitor_id,
        visit_id,
        visit_time,
        device_type,
        app_type,
        os_group,
        src,
        src_detail,
        geo_id,
        geo_country,
        geo_region,
        geo_city
    FROM {{ ref('stg_piano__composer_events') }}
    WHERE event_name = 'vx.conversion'

),

ranked_matches AS (

    SELECT
        ofs.*,
        ons.* EXCLUDE (conversion_time),
        ROW_NUMBER() OVER (
            PARTITION BY ofs.conversion_id 
            ORDER BY ABS(DATEDIFF(second, ofs.conversion_time, ons.conversion_time)) 
        ) AS ranking
    FROM offsite_conversions ofs
    LEFT JOIN onsite_conversions ons
        ON ABS(DATEDIFF(HOUR, ofs.conversion_time, ons.conversion_time)) <= 1  -- window in hours

)

SELECT
    conversion_id,
    subscription_id,
    visitor_id,
    user_id,
    visit_id,
    visit_time,
    device_type,
    app_type,
    os_group,
    conversion_time,
    term_id,
    term_name,
    term_offer_id,
    term_offer_name,
    billing_period,
    subscription_period_number,
    src,
    src_detail,
    geo_id,
    geo_country,
    geo_region,
    geo_city
FROM ranked_matches
WHERE
    visitor_id IS NOT NULL
    AND ranking = 1
