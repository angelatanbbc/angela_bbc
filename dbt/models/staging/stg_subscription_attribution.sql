{{config(materialized="view")}}

/* ============================================================
   STEP 1: Identify valid signup (conversion) events
   ------------------------------------------------------------
   - Find the earliest vx.conversion per visitor + pageview
   - Exclude internal / employee promo codes
   - Restrict to eligible experiences and offers
   ============================================================ */
   
with ntemp as (SELECT
   visitor_id,
   pageview_id,
   min(event_time) as signup_event,
FROM {{ source('studios_piano', 'studios_piano_events') }}
WHERE 1=1
    AND TO_DATE(event_time) > '2025-06-25'
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
  group by all
),

/* ============================================================
   STEP 2: Reconstruct visitor identity at pageview level
   ------------------------------------------------------------
   - Join all relevant events to signup pageviews
   - Capture the visitor_id from the page.display event
     (handles cases where visitor_id changes mid-session)
   ============================================================ */
   
ntemp2 as (
 select s.event_time,
 s.event_name,
 s.visitor_id,
 t.signup_event,
 t.pageview_id,
MAX(CASE 
    WHEN s.event_name = 'page.display' 
    THEN s.visitor_id 
    ELSE NULL 
END) OVER (PARTITION BY t.pageview_id) AS new_visitor_id
 from {{ source('studios_piano', 'studios_piano_events') }} s 

 join ntemp t 
 on s.pageview_id=t.pageview_id
 where 1=1
 AND TO_DATE(event_time) > '2025-06-25'
 AND (event_name in('page.display','vx.conversion') OR av_playback_duration > 0 )
),

/* ============================================================
   STEP 3: Final signup table with resolved visitor identity
   ------------------------------------------------------------
   - One row per signup
   - Use pageview-level visitor_id when available
   ============================================================ */

signups as (select
signup_event,
pageview_id,
coalesce (new_visitor_id,visitor_id) as visitor_id
from ntemp2
where event_name ='vx.conversion'

  )

/* ============================================================
   STEP 4: Pull all relevant events in the 30-day pre-signup window
   ------------------------------------------------------------
   - Join events to subscribers
   - Restrict to page views and conversions
   - Extract attribution parameters from URLs
   ============================================================ */
   
select 
    event_time as event_date, 
    DATE(event_time) AS event_day,
    s.event_url_full, 
    s.visitor_id as visitor_id_original,
    coalesce(MAX(CASE 
        WHEN s.event_name = 'page.display' 
        THEN s.visitor_id 
        ELSE NULL 
    END) OVER (PARTITION BY s.pageview_id) , s.visitor_id) AS visitor_id,
    s.visit_id, 
    s.pageview_id,
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
    s.src_sl_term,
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
    s.billing_period,
    s.trial_duration,
    s.subscription_id,
    s.subscription_action,
    s.subscription_period_number,
    s.cart_turnovertaxfree,
    vs.signup_event, 
    vs.pageview_id as signup_pageview_id,
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
  FROM 
    {{ source('studios_piano', 'studios_piano_events') }} s 
    inner join Signups vs on s.visitor_id = vs.visitor_id 
  WHERE 
    1 = 1 
    AND TO_DATE(event_time) > '2025-05-25'
    and (event_name = 'page.display' OR event_name='vx.conversion')
    and DATEDIFF(day, s.event_time, vs.signup_event) <= 30
    and DATEDIFF(day, s.event_time, vs.signup_event) >= 0
