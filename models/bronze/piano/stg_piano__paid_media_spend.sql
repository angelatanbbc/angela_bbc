{{ config(materialized="view") }}

------------------------------------------------ SECTION 1 --------------------------------------------
-- This section gathers all the essential data from the ps_piano_events, basic_ad, and country_spend tables
WITH setup AS (
    SELECT
        TO_DATE(event_time) AS event_date,
        site_id,
        visitor_id,
        user_id,
        event_name,
        event_id,
        page,
        src_bbc_team,
        geo_country,
        src_ptr_name,
        src_campaign,
        src_adset_name,
        src_creative_id,
        -- src_campaign_id_1,
        av_session_id,
        av_playback_duration,
        device_type,
        app_type,
        SUBSTRING(
            event_url_full,
            POSITION('at_bbc_team=' IN event_url_full) + LENGTH('at_bbc_team='),
            POSITION(
                '&at' IN SUBSTRING(
                    event_url_full,
                    POSITION('at_bbc_team=' IN event_url_full)
                    + LENGTH('at_bbc_team=')
                    + 1
                )
            )
        ) AS at_bbc_team
    FROM {{ source('studios_piano', 'studios_piano_events') }}
    WHERE
        1 = 1
        AND TO_DATE(event_time) > '2025-10-01'
        -- AND event_time BETWEEN DATEADD(month, -2, CURRENT_DATE) AND CURRENT_DATE
        -- AND src_bbc_team = '8ms'
        AND page NOT IN (
            'keepalive',
            'page.view.page',
            'onboarding.page',
            'error.page',
            'notification.page'
        )
        AND (event_name = 'page.display' OR av_playback_duration > 0)
),

ad_data_facebook AS (
    SELECT
        date,
        ad_id,
        account_id,
        ad_name,
        adset_name,
        impressions,
        reach,
        inline_link_clicks,
        spend AS spend
    FROM {{ source('FACEBOOK_ADS', 'basic_ad') }}
    WHERE
        1 = 1
        AND (date) > '2025-10-01'
        -- and date BETWEEN DATEADD(month, -2, CURRENT_DATE) AND CURRENT_DATE
        AND account_id = 1608552529481933
        AND ad_name NOT LIKE '%POD%'
),

-- Joins the setup and ad_data tables
staging_facebook AS (
    SELECT
        e.*,
        a.event_date,
        a.site_id,
        CASE
            WHEN a.visitor_id IS NULL THEN NULL ELSE
                cast(a.visitor_id as VARCHAR)
        END AS visitor_id,
        a.user_id,
        a.event_name,
        a.event_id,
        a.page,
        COALESCE(a.src_bbc_team, a.at_bbc_team) AS src_bbc_team,
        a.geo_country,
        a.src_ptr_name,
        a.src_campaign,
        a.src_adset_name,
        a.src_creative_id,
        -- a.src_campaign_id_1,
        a.av_session_id,
        a.av_playback_duration,
        a.device_type,
        a.app_type
    FROM ad_data_facebook e
    LEFT JOIN setup a
        ON
            e.date = a.event_date
            AND e.ad_id = a.src_creative_id
),

final_facebook AS (
    SELECT
        *,
        COUNT(DISTINCT visitor_id)
            OVER (PARTITION BY ad_id, date)
            AS total_visitors,
        CASE
            WHEN visitor_id IS NULL THEN spend ELSE
                spend
                / COUNT(DISTINCT visitor_id) OVER (PARTITION BY ad_id, date)
        END AS spend_per_visitor,
        CASE
            WHEN visitor_id IS NULL THEN impressions ELSE
                impressions
                / COUNT(DISTINCT visitor_id) OVER (PARTITION BY ad_id, date)
        END AS impressions_per_visitor,
        CASE
            WHEN visitor_id IS NULL THEN reach ELSE
                reach
                / COUNT(DISTINCT visitor_id) OVER (PARTITION BY ad_id, date)
        END AS reach_per_visitor,
        CASE
            WHEN visitor_id IS NULL THEN inline_link_clicks ELSE
                inline_link_clicks
                / COUNT(DISTINCT visitor_id) OVER (PARTITION BY ad_id, date)
        END AS inline_link_clicks_per_visitor
    FROM staging_facebook
    WHERE 1 = 1
-- and ad_id=120231784754050423
-- and visitor_id is null
-- order by event_Date ASC , visitor_id asc
),

ad_data_google AS (
    SELECT
        cast(TO_DATE(date, 'DD/MM/YYYY') as DATE) AS date,
        ad_id,
        account_id,
        ad_name,
        adset_name,
        REGEXP_SUBSTR(ad_name, '(DBS|8MS)') AS src_bbc_team_v2,
        spend AS spend
    FROM {{ source('GOOGLE_ADS', 'STG_GOOGLE_ADS') }}
    WHERE
        1 = 1
        AND (cast(TO_DATE(date, 'DD/MM/YYYY') as DATE) > '2025-10-01')
        AND TRY_TO_DATE(date, 'DD/MM/YYYY') IS NOT NULL
),

-- Joins the setup and ad_data tables
staging_google AS (
    SELECT
        e.*,
        a.event_date,
        a.site_id,
        CASE
            WHEN a.visitor_id IS NULL THEN NULL ELSE
                cast(a.visitor_id as VARCHAR)
        END AS visitor_id,
        a.user_id,
        a.event_name,
        a.event_id,
        a.page,
        COALESCE(a.src_bbc_team, a.at_bbc_team, e.src_bbc_team_v2)
            AS src_bbc_team,
        a.geo_country,
        a.src_ptr_name,
        a.src_campaign,
        a.src_adset_name,
        a.src_creative_id,
        -- a.src_campaign_id_1,
        a.av_session_id,
        a.av_playback_duration,
        a.device_type,
        a.app_type
    FROM ad_data_google e
    LEFT JOIN setup a
        ON
            e.date = a.event_date
            AND CAST(e.ad_id AS VARCHAR) = a.src_creative_id
-- AND e.ad_id=a.src_creative_id
),

final_google AS (
    SELECT
        *,
        COUNT(DISTINCT visitor_id)
            OVER (PARTITION BY ad_id, date)
            AS total_visitors,
        CASE
            WHEN visitor_id IS NULL THEN spend ELSE
                spend
                / COUNT(DISTINCT visitor_id) OVER (PARTITION BY ad_id, date)
        END AS spend_per_visitor
    FROM staging_google
    WHERE 1 = 1
-- and ad_id=120231784754050423
-- and visitor_id is null
-- order by event_Date ASC , visitor_id asc
)

SELECT DISTINCT
    COALESCE(event_date, date) AS event_date,
    src_adset_name,
    src_bbc_team AS src_bbc_team_o,
    src_campaign,
    src_creative_id,
    src_ptr_name,
    account_id,
    visitor_id,
    spend_per_visitor,
    impressions_per_visitor,
    reach_per_visitor,
    inline_link_clicks_per_visitor,
    cast(ad_id as STRING) AS ad_id,
    ad_name,
    COALESCE(
        NULLIF(src_bbc_team, ''),
        MAX(NULLIF(src_bbc_team, ''))
            OVER (PARTITION BY ad_name)
    ) AS src_bbc_team,
    adset_name,
    'facebook' AS source
FROM final_facebook

UNION ALL

SELECT DISTINCT
    COALESCE(event_date, date) AS event_date,
    src_adset_name,
    src_bbc_team AS src_bbc_team_o,
    src_campaign,
    src_creative_id,
    src_ptr_name,
    account_id,
    visitor_id,
    spend_per_visitor,
    NULL AS impressions_per_visitor,
    NULL AS reach_per_visitor,
    NULL AS inline_link_clicks_per_visitor,
    cast(ad_id as STRING) AS ad_id,
    ad_name,
    COALESCE(
        NULLIF(src_bbc_team, ''),
        MAX(NULLIF(src_bbc_team, ''))
            OVER (PARTITION BY ad_name)
    ) AS src_bbc_team,
    adset_name,
    CASE WHEN LENGTH(ad_id) = 14 THEN 'microsoft' ELSE 'google' END AS source
FROM final_google
