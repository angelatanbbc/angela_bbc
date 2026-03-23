{{ config(
    materialized="view",
    tags=["piano", "intermediate"]
) }}

SELECT
    event_id,
    site_id,
    visit_id,
    visitor_id,
    user_id,
    event_name,
    event_time,
    event_url,
    visit_time,
    visit_time_utc,
    src,
    src_detail,
    app_type,
    device_type,
    os_group,
    {{ dbt_utils.generate_surrogate_key(['geo_country', 'geo_region', 'geo_city']) }} AS geo_id,
    geo_country,
    geo_region,
    geo_city,
    conversion_id,
    subscription_id,
    term[0]['term_id2']::VARCHAR AS term_id,
    term[0]['term_name']::VARCHAR AS term_name,
    term[0]['term_type']::VARCHAR AS term_type,
    term_offer_id,
    term_offer_name,
    billing_period,
    subscription_action,
    subscription_period_number,
    cart_turnovertaxfree

FROM {{ ref('stg_piano__events') }}

WHERE
    event_time::DATE > '2025-06-25'
    AND event_name ILIKE '%offsite%'
