{{config(materialized="view")}}

-- Selects the event_date, visitor_id of the visitors on the day they subscribe
with Signups as (
  SELECT
   visitor_id,
   min(event_time) as signup_event,

FROM {{ source('studios_piano', 'studios_piano_events') }}
WHERE 1=1
  AND TO_DATE(event_time) > '2025-06-25'
  -- AND site_id = 638824
  AND event_name IN ('vx.conversion')
  AND (vx_promo_code NOT IN ('BBCEMPLOYEE','BBCEDITORIAL','BBCACCOUNT','') OR vx_promo_code IS null)
  AND (
        experience_name LIKE '%00%' 
        OR experience_name IS NULL
      )
  AND (
        term_offer_name IS NULL 
        OR term_offer_name = 'BBC Subscription'
      )
 group by 1
  )
    
-- Selects the relevant column and inner joins with the visitors that subscribed and looks at the events 30 days before the signup date

  select 
    event_time as event_date, 
    DATE(event_time) AS event_day,
    s.event_url_full, 
    s.visitor_id,
    s.visit_id, 
    s.connection_organisation, 
    s.src_bbc_team, 
    s.src_ptr_name,
    case when s.src_detail = 'buy-eu.piano.io' then null else s.src_detail end as src_detail,
    s.src, 
    s.src_organic, 
    s.src_organic_detail,
    s.src_campaign,
    s.src_adset_name,
    s.src_medium,
    s.src_creative_id,
    s.src_creation,
    s.src_campaign_type,
    s.src_format,
    s.content_pillar, 
    s.geo_country, 
    s.browser, 
    s.device_type, 
    s.site_id,
    s.event_name,
    s.vx_promo_code,
    vs.signup_event, 
REGEXP_SUBSTR(event_url_full, 'at_link_origin=([^&]+)', 1, 1, '', 1) AS link_origin,
REGEXP_SUBSTR(event_url_full, 'at_campaign=([^&]+)', 1, 1, '', 1) AS signup_page,
REGEXP_SUBSTR(event_url_full, 'at_ptr_name=([^&]+)', 1, 1, '', 1) AS at_ptr_name,
REGEXP_SUBSTR(event_url_full, 'at_adset_name=([^&]+)', 1, 1, '', 1) AS at_adset_name,
REGEXP_SUBSTR(event_url_full, 'at_creative_id=([^&]+)', 1, 1, '', 1) AS at_creative_id,
REGEXP_SUBSTR(event_url_full, 'at_adset_id=([^&]+)', 1, 1, '', 1) AS at_adset_id,
REGEXP_SUBSTR(event_url_full, 'at_objective=([^&]+)', 1, 1, '', 1) AS at_objective,
REGEXP_SUBSTR(event_url_full, 'at_medium=([^&]+)', 1, 1, '', 1) AS at_medium,
REGEXP_SUBSTR(event_url_full, 'at_bbc_team=([^&]+)', 1, 1, '', 1) AS at_bbc_team,
REGEXP_SUBSTR(event_url_full, 'at_matchtype=([^&]+)', 1, 1, '', 1) AS at_matchtype,
REGEXP_SUBSTR(event_url_full, 'at_keyword=([^&]+)', 1, 1, '', 1) AS at_keyword,
REGEXP_SUBSTR(event_url_full, 'at_creation=([^&]+)', 1, 1, '', 1) AS at_creation,
REGEXP_SUBSTR(event_url_full, 'at_campaign_name=([^&]+)', 1, 1, '', 1) AS at_campaign_name,

  from 
    {{ source('studios_piano', 'studios_piano_events') }} s 
    inner join Signups vs on s.visitor_id = vs.visitor_id 
  WHERE 
    1 = 1 
    AND TO_DATE(event_time) > '2025-05-25'
    -- and page NOT IN ('keepalive', 'page.view.page', 'onboarding.page', 'error.page', 'notification.page')
    and (event_name = 'page.display' OR event_name='vx.conversion')
    and DATEDIFF(day, s.event_time, vs.signup_event) <= 30
    and DATEDIFF(day, s.event_time, vs.signup_event) >= 0
