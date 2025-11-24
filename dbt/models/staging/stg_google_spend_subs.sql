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
    src_campaign_id_1,
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
        TO_DATE(date, 'DD/MM/YYYY')::DATE AS date,
        ad_id,
        account_id,
        ad_name,
        adset_name,
        TRIM(SPLIT_PART(ad_name, '|', 2)) AS src_bbc_team_v2,
        spend as spend
    FROM SDP_SANDBOX.DNS.CGM_GOOGLE_ADS
    where 1=1
    AND TRY_TO_DATE(date, 'DD/MM/YYYY') IS NOT NULL

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
    coalesce(a.src_bbc_team,a.at_bbc_team,e.src_bbc_team_v2) as src_bbc_team,
    a.geo_country,
    a.src_ptr_name,
    a.src_campaign,
    a.src_adset_name,
    a.src_creative_id,
    a.src_campaign_id_1,
    a.av_session_id,
    a.av_playback_duration,
    a.device_type,
    a.app_type
FROM ad_data e
LEFT JOIN setup a 
    ON e.date=a.event_date
    AND CAST(e.ad_id AS VARCHAR) = a.src_creative_id