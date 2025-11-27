{{config(materialized="view")}}

------------------------------------------------ SECTION 1 --------------------------------------------
-- This section gathers all the essential data from the ps_piano_events, basic_ad, and country_spend tables
WITH setup AS (
  SELECT 
    to_date(event_time) AS event_date,
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
           POSITION('at_bbc_team=' IN event_url_full) + LENGTH('at_bbc_team=') , 
           POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_bbc_team=' IN event_url_full) + LENGTH('at_bbc_team=') + 1)) 
       ) AS at_bbc_team
  FROM {{ source('studios_piano', 'studios_piano_events') }}
  WHERE 1=1
  AND TO_DATE(event_time) > '2025-10-01'
    -- AND event_time BETWEEN DATEADD(month, -2, CURRENT_DATE) AND CURRENT_DATE
    -- AND src_bbc_team = '8ms'
    AND page NOT IN ('keepalive', 'page.view.page', 'onboarding.page', 'error.page', 'notification.page')
    AND (event_name = 'page.display' OR av_playback_duration > 0)
),

ad_data as (
    SELECT 
        date,
        ad_id,
        account_id,
        ad_name,
        adset_name,
        spend as spend
    FROM {{ source('FACEBOOK_ADS', 'basic_ad') }}
    where 1=1 
    AND TO_DATE(date) > '2025-10-01'
    -- and date BETWEEN DATEADD(month, -2, CURRENT_DATE) AND CURRENT_DATE
    and account_id=1608552529481933
    and ad_name not like '%POD%'
)

-- Joins the setup and ad_data tables
SELECT 
    e.*,
    a.event_date,
    a.site_id,
    case when a.visitor_id is null then null else cast(a.visitor_id as varchar) end as visitor_id, 
    a.user_id,
    a.event_name,
    a.event_id,
    a.page,
    coalesce(a.src_bbc_team,a.at_bbc_team) as src_bbc_team,
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
FROM ad_data e
LEFT JOIN setup a 
    ON e.date=a.event_date
    AND e.ad_id=a.src_creative_id