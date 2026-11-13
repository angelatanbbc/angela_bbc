{{
    config(
        materialized="table",
        tags=["newsletter", "tableau"]
    )
}}

-- column names follow the newsletter acquisition dashboard; text is capped at VARCHAR(512) for Tableau
WITH page_visits AS (

    SELECT
        'page.display'::VARCHAR(32) AS event_name,
        event_date AS event_day,
        visitor_id,
        user_id,
        visit_id,
        NULL::VARCHAR(512) AS newsletter_title,
        src,
        src_detail,
        src_format,
        src_medium,
        src_campaign,
        src_bbc_team,
        src_ptr_name,
        at_link_origin,
        at_format,
        account_status,
        device_platform_id,
        browser_group,
        geo_country,
        signed_up,
        titles_signed_up,
        page_displays,
        NULL::BOOLEAN AS is_latest_for_user_title,
        is_suspected_automated
    FROM {{ ref('fct_newsletter_page_visits') }}

),

latest_signups AS (

    SELECT
        'newsletter.subscribe'::VARCHAR(32) AS event_name,
        event_date AS event_day,
        visitor_id,
        user_id,
        visit_id,
        newsletter_title,
        src,
        src_detail,
        src_format,
        src_medium,
        src_campaign,
        src_bbc_team,
        src_ptr_name,
        at_link_origin,
        at_format,
        account_status,
        device_platform_id,
        browser_group,
        geo_country,
        TRUE AS signed_up,
        NULL::NUMBER AS titles_signed_up,
        NULL::NUMBER AS page_displays,
        is_latest_for_user_title,
        is_suspected_automated
    FROM {{ ref('fct_newsletter_signups') }}
    WHERE is_latest_for_visitor_title

),

activity AS (

    SELECT * FROM page_visits
    UNION ALL
    SELECT * FROM latest_signups

)

SELECT
    a.event_name,
    a.event_day,
    HEX_ENCODE(a.visitor_id)::VARCHAR(64) AS visitor_id,
    LEFT(a.user_id, 64)::VARCHAR(64) AS user_id,
    HEX_ENCODE(a.visit_id)::VARCHAR(64) AS visit_id,
    a.newsletter_title,
    LEFT(a.src, 512)::VARCHAR(512) AS src,
    LEFT(a.src_detail, 512)::VARCHAR(512) AS src_detail,
    LEFT(a.src_format, 512)::VARCHAR(512) AS src_format,
    LEFT(a.src_medium, 512)::VARCHAR(512) AS src_medium,
    LEFT(a.src_campaign, 512)::VARCHAR(512) AS src_campaign,
    LEFT(a.src_bbc_team, 64)::VARCHAR(64) AS src_bbc_team,
    LEFT(a.src_ptr_name, 512)::VARCHAR(512) AS src_ptr_name,
    LEFT(a.at_link_origin, 512)::VARCHAR(512) AS link_origin,
    LEFT(a.at_format, 512)::VARCHAR(512) AS at_format,
    a.account_status::VARCHAR(32) AS account_status,
    LEFT(dp.device_type, 64)::VARCHAR(64) AS device_type,
    LEFT(dp.os_group, 64)::VARCHAR(64) AS os_group,
    LEFT(a.browser_group, 64)::VARCHAR(64) AS browser_group,
    LEFT(a.geo_country, 64)::VARCHAR(64) AS geo_country,
    a.signed_up,
    a.titles_signed_up,
    a.page_displays,
    a.is_latest_for_user_title,
    a.is_suspected_automated
FROM activity a
LEFT JOIN {{ ref('dim_device_platform') }} dp ON a.device_platform_id = dp.device_platform_id
