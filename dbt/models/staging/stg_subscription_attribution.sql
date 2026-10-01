{{config(materialized="view")}}

/* ============================================================
   CROSS-COOKIE CORRECTIONS (added 2026-10)
   ------------------------------------------------------------
   STEPS 1-4 are the original model, unchanged: the journey
   follows the checkout page view's visitor_id only. STEPS 5-9
   correct three things that made Paid look smaller than it is.

   1. The buyer's other cookies. A buyer who registers or signs
      in on the way to checkout often comes back on a new
      visitor_id, so the browsing before it - often the ad
      click - was lost. Added: the page views, in the same
      30-day window, of the buyer's other cookies, linked by
        account      - the cookie's page views carry the buyer's
                       user_id ('unidentified-user', a Piano
                       placeholder on ~100K cookies, never links)
        registration - the cookie on the buyer's
                       registration.complete event
        device       - the same device_first_party_id (it
                       survives sign-in), unless that browser had
                       more than 20 cookies in the window or the
                       cookie carries a different real account.
      visitor_id stays the checkout cookie (the journey key
      downstream), visitor_id_original is the event's own cookie
      and link_type says how it was linked.
   2. The sign-in round trip is not a touchpoint. The page
      reached straight back from account.bbc.com (usually
      subscribe.page, ~2 min before the purchase) is a checkout
      step that Piano labels 'Direct traffic', and it took a
      share of the credit from the ad. Dropped, unless a
      journey has nothing else.
   3. Lost agency tag. ~11% of visits from 8MS / DBS Meta ads
      arrive without at_bbc_team although the ad is tagged, so
      they were filed under 'Social media'. An empty
      src_bbc_team is filled from the ad's creative url tags
      (src_creative_id, else at_creative_id), else from an
      8ms_ / dbs_ campaign name on a Facebook / Instagram
      visit. bbc_team_source says which.

   Scope: only sign-ups bought on, and page views on,
   var('subscription_site_ids') count (www.test.bbc.com and
   other sites are out).
   Effect, sign-ups 16 Aug - 28 Sep 2026 (full 30-day look-back):
   Paid 924.2 -> 1,102.6 (+19%); 1,003 -> 1,276 journeys with a
   paid touch. Not handled: Facebook / Instagram visits with no
   tags at all (some are ads, most are organic shares).
   ============================================================ */

{% set sites = var('subscription_site_ids') | join(', ') %}

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
   subscription_id,
   billing_period,
   cart_turnovertaxfree,
   min(event_time) as signup_event,
FROM {{ source('studios_piano', 'studios_piano_events') }}
WHERE 1=1
    AND TO_DATE(event_time) > '2025-06-25'
  AND event_name IN ('vx.conversion')
  AND (vx_promo_code NOT IN ('BBCEMPLOYEE','BBCEDITORIAL','BBCACCOUNT','') OR vx_promo_code IS null)
  AND (app_type!='mobile-app' or app_type is null)
  -- AND (
  --       experience_name LIKE '%00%' 
  --       OR experience_name IS NULL
  --     )
  -- AND (
  --       term_offer_name IS NULL 
  --       OR term_offer_name = 'BBC Subscription'
  --     )
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
 t.subscription_id,
 t.billing_period,
 t.cart_turnovertaxfree,
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

signups AS (
  SELECT
    signup_event,
    pageview_id,
    visitor_id,
    subscription_id,
    billing_period,
    cart_turnovertaxfree,
    LAG(signup_event) OVER (
      PARTITION BY visitor_id
      ORDER BY signup_event
    ) AS prev_signup_event
  FROM (
    SELECT
      signup_event,
      pageview_id,
      subscription_id,
      billing_period,
      cart_turnovertaxfree,
      COALESCE(new_visitor_id, visitor_id) AS visitor_id
    FROM ntemp2
    WHERE event_name = 'vx.conversion'
  )
),

/* ============================================================
   STEP 4: Pull all relevant events in the 30-day pre-signup window
   ------------------------------------------------------------
   - Join events to subscribers
   - Restrict to page views and conversions
   - Extract attribution parameters from URLs
   ============================================================ */
   
journeys as (
select 
    event_time as event_date, 
    DATE(event_time) AS event_day,
    s.event_url_full, 
    s.visitor_id as visitor_id_original,
    coalesce(MAX(CASE 
        WHEN s.event_name = 'page.display' 
        THEN s.visitor_id 
        ELSE NULL 
    END) OVER (PARTITION BY vs.pageview_id) , s.visitor_id) AS visitor_id,
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
    vs.billing_period,
    s.trial_duration,
    vs.subscription_id,
    s.subscription_action,
    s.subscription_period_number,
    vs.cart_turnovertaxfree,
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
    AND s.event_time <= vs.signup_event
    AND (
       s.event_time > vs.prev_signup_event
       OR vs.prev_signup_event IS NULL
        )
  WHERE 
    1 = 1 
    AND TO_DATE(event_time) > '2025-05-25'
    and (event_name = 'page.display' OR event_name='vx.conversion')
    and DATEDIFF(day, s.event_time, vs.signup_event) <= 30
    and DATEDIFF(day, s.event_time, vs.signup_event) >= 0
),

/* ============================================================
   STEP 5: The buyer's account, browser and sign-up site
   ------------------------------------------------------------
   - Read from the checkout page view (conversion + display)
   - One row per journey, with STEP 3's previous-sign-up cut
   - Only sign-ups bought on a counted site stay in scope
   ============================================================ */

checkout_referrers as (   -- where each page view already in the journey came from
    select pageview_id, max(split_part(src_referrer_url, '/', 3)) as referrer_host
    from {{ source('studios_piano', 'studios_piano_events') }}
    where TO_DATE(event_time) > '2025-05-25'
      and event_name = 'page.display'
      and pageview_id in (select pageview_id from journeys)
    group by 1
),

journey_signups as (   -- a journey can carry more than one sign-up row (subscription x billing x amount)
    select distinct visitor_id, signup_event, signup_pageview_id, subscription_id, billing_period, cart_turnovertaxfree
    from journeys
),

buyer_ids as (
    select pageview_id,
           max(iff(user_id ilike 'unidentified%', null, nullif(user_id, ''))) as buyer_user_id,
           max(device_first_party_id)                                         as buyer_device_id,
           max(iff(event_name = 'vx.conversion', site_id, null))              as signup_site_id
    from {{ source('studios_piano', 'studios_piano_events') }}
    where TO_DATE(event_time) > '2025-05-25'
      and event_name in ('vx.conversion', 'page.display')
      and pageview_id in (select signup_pageview_id from journey_signups)
    group by 1
),

journey_keys as (
    select k.visitor_id, k.signup_event, k.signup_pageview_id, b.buyer_user_id, b.buyer_device_id, b.signup_site_id,
           lag(k.signup_event) over (partition by k.visitor_id order by k.signup_event) as prev_signup_event
    from (select distinct visitor_id, signup_event, signup_pageview_id from journey_signups) k
    left join buyer_ids b on b.pageview_id = k.signup_pageview_id
),

in_scope as (
    select distinct visitor_id, signup_event
    from journey_keys
    where signup_site_id in ({{ sites }})
),

/* ============================================================
   STEP 6: Link the buyer's other cookies
   ------------------------------------------------------------
   - account / registration / device, each judged inside the
     journey's own 30-day window
   - A cookie linked more than one way keeps one link_type
   ============================================================ */

evidence as (   -- page views carrying a buyer's account or seen on a buyer's browser
    select visitor_id, device_first_party_id as device_id, event_time,
           iff(user_id ilike 'unidentified%', null, nullif(user_id, '')) as user_id
    from {{ source('studios_piano', 'studios_piano_events') }}
    where TO_DATE(event_time) > '2025-05-25'
      and event_name = 'page.display'
      and (user_id in (select buyer_user_id from journey_keys)
           or device_first_party_id in (select buyer_device_id from journey_keys))
),

registrations as (
    select visitor_id, event_time, nullif(user_id, '') as user_id
    from {{ source('studios_piano', 'studios_piano_events') }}
    where TO_DATE(event_time) > '2025-05-25'
      and event_name = 'registration.complete'
      and user_id in (select buyer_user_id from journey_keys)
),

browser_size as (   -- cookies per buyer browser inside the journey window
    select k.visitor_id, k.signup_event, count(distinct e.visitor_id) as n_cookies
    from journey_keys k
    join evidence e on e.device_id = k.buyer_device_id
                   and e.event_time <= k.signup_event and datediff(day, e.event_time, k.signup_event) <= 30
    group by 1, 2
),

links as (
    select k.visitor_id, k.signup_event, e.visitor_id as linked_visitor, 'account' as link_type
    from journey_keys k
    join evidence e on e.user_id = k.buyer_user_id
                   and e.event_time <= k.signup_event and datediff(day, e.event_time, k.signup_event) <= 30
    where e.visitor_id <> k.visitor_id

    union all

    select k.visitor_id, k.signup_event, g.visitor_id, 'registration'
    from journey_keys k
    join registrations g on g.user_id = k.buyer_user_id
                        and g.event_time <= k.signup_event and datediff(day, g.event_time, k.signup_event) <= 30
    where g.visitor_id <> k.visitor_id

    union all

    select k.visitor_id, k.signup_event, e.visitor_id, 'device'
    from journey_keys k
    join browser_size b on b.visitor_id = k.visitor_id and b.signup_event = k.signup_event and b.n_cookies <= 20
    join evidence e on e.device_id = k.buyer_device_id
                   and e.event_time <= k.signup_event and datediff(day, e.event_time, k.signup_event) <= 30
    where e.visitor_id <> k.visitor_id
    group by 1, 2, 3
    having count_if(e.user_id is not null and e.user_id <> coalesce(k.buyer_user_id, '')) = 0   -- no other real account
),

link_set as (
    select visitor_id, signup_event, linked_visitor,
           min_by(link_type, decode(link_type, 'account', 1, 'registration', 2, 3)) as link_type
    from links
    group by 1, 2, 3
),

/* ============================================================
   STEP 7: The linked cookies' page views
   ------------------------------------------------------------
   - Shaped exactly like STEP 4's rows, same window and cut
   - Page views only: another cookie's vx.conversion would be
     a different purchase
   ============================================================ */

linked_events as (
    select
        e.event_time as event_date,
        date(e.event_time) as event_day,
        e.event_url_full,
        e.visitor_id as visitor_id_original,
        s.visitor_id,                                   -- the checkout cookie: the journey key
        e.visit_id,
        e.pageview_id,
        e.connection_organisation,
        e.src_bbc_team,
        e.src_ptr_name,
        case when e.src_detail = 'buy-eu.piano.io' then null else e.src_detail end as src_detail,
        e.src,
        e.src_organic,
        e.src_organic_detail,
        e.src_campaign,
        e.src_adset_name,
        e.src_medium,
        e.src_sl_term,
        e.src_creative_id,
        e.src_creation,
        e.src_campaign_type,
        e.src_format,
        e.content_pillar,
        e.geo_country,
        e.browser,
        e.device_type,
        e.site_id,
        e.event_name,
        e.vx_promo_code,
        s.billing_period,
        e.trial_duration,
        s.subscription_id,
        e.subscription_action,
        e.subscription_period_number,
        s.cart_turnovertaxfree,
        s.signup_event,
        s.signup_pageview_id,
        regexp_substr(e.event_url_full, 'at_link_origin=([^&]+)', 1, 1, '', 1)   as link_origin,
        regexp_substr(e.event_url_full, 'at_campaign=([^&]+)', 1, 1, '', 1)      as signup_page,
        regexp_substr(e.event_url_full, 'at_ptr_name=([^&]+)', 1, 1, '', 1)      as at_ptr_name,
        regexp_substr(e.event_url_full, 'at_adset_name=([^&]+)', 1, 1, '', 1)    as at_adset_name,
        regexp_substr(e.event_url_full, 'at_creative_id=([^&]+)', 1, 1, '', 1)   as at_creative_id,
        regexp_substr(e.event_url_full, 'at_adset_id=([^&]+)', 1, 1, '', 1)      as at_adset_id,
        regexp_substr(e.event_url_full, 'at_objective=([^&]+)', 1, 1, '', 1)     as at_objective,
        regexp_substr(e.event_url_full, 'at_medium=([^&]+)', 1, 1, '', 1)        as at_medium,
        regexp_substr(e.event_url_full, 'at_bbc_team=([^&]+)', 1, 1, '', 1)      as at_bbc_team,
        regexp_substr(e.event_url_full, 'at_matchtype=([^&]+)', 1, 1, '', 1)     as at_matchtype,
        regexp_substr(e.event_url_full, 'at_keyword=([^&]+)', 1, 1, '', 1)       as at_keyword,
        regexp_substr(e.event_url_full, 'at_creation=([^&]+)', 1, 1, '', 1)      as at_creation,
        regexp_substr(e.event_url_full, 'at_campaign_name=([^&]+)', 1, 1, '', 1) as at_campaign_name,
        l.link_type,
        split_part(e.src_referrer_url, '/', 3) as referrer_host
    from {{ source('studios_piano', 'studios_piano_events') }} e
    join link_set l        on l.linked_visitor = e.visitor_id
    join journey_keys k    on k.visitor_id = l.visitor_id and k.signup_event = l.signup_event
    join in_scope i        on i.visitor_id = l.visitor_id and i.signup_event = l.signup_event
    join journey_signups s on s.visitor_id = l.visitor_id and s.signup_event = l.signup_event
    where TO_DATE(e.event_time) > '2025-05-25'
      and e.event_name = 'page.display'
      and e.site_id in ({{ sites }})
      and e.event_time <= k.signup_event
      and (e.event_time > k.prev_signup_event or k.prev_signup_event is null)
      and datediff(day, e.event_time, k.signup_event) <= 30
      and datediff(day, e.event_time, k.signup_event) >= 0
),

/* ============================================================
   STEP 8: The agency of every 8MS / DBS Meta ad
   ------------------------------------------------------------
   - From the creative's url tags (at_bbc_team), by ad_id
     (Piano's src_creative_id is the Meta ad_id)
   ============================================================ */

ad_team as (
    select ads.ad_id::varchar as ad_id, max(lower(trim(creatives.at_bbc_team))) as bbc_team
    from {{ ref('stg_facebook_ads__ad_history') }} ads
    join {{ ref('int_facebook_ads__creative_history') }} creatives
        on ads.creative_id = creatives.creative_id
        and ads.source_relation = creatives.source_relation
    where ads.is_most_recent_record = true
      and lower(trim(creatives.at_bbc_team)) in ('8ms', 'dbs')
    group by 1
),

/* ============================================================
   STEP 9: Final journey
   ------------------------------------------------------------
   - STEP 4's rows (in-scope sign-ups, counted sites) plus the
     linked cookies' page views
   - Lost agency tag filled from the ad, else the campaign name
   - Sign-in round trip dropped unless it is all a journey has
   ============================================================ */

all_rows as (
    select
        j.event_date, j.event_day, j.event_url_full, j.visitor_id_original, j.visitor_id, j.visit_id, j.pageview_id,
        j.connection_organisation, j.src_bbc_team, j.src_ptr_name, j.src_detail, j.src, j.src_organic,
        j.src_organic_detail, j.src_campaign, j.src_adset_name, j.src_medium, j.src_sl_term, j.src_creative_id,
        j.src_creation, j.src_campaign_type, j.src_format, j.content_pillar, j.geo_country, j.browser,
        j.device_type, j.site_id, j.event_name, j.vx_promo_code, j.billing_period, j.trial_duration,
        j.subscription_id, j.subscription_action, j.subscription_period_number, j.cart_turnovertaxfree,
        j.signup_event, j.signup_pageview_id, j.link_origin, j.signup_page, j.at_ptr_name, j.at_adset_name,
        j.at_creative_id, j.at_adset_id, j.at_objective, j.at_medium, j.at_bbc_team, j.at_matchtype,
        j.at_keyword, j.at_creation, j.at_campaign_name,
        'checkout cookie' as link_type,
        coalesce(j.event_name = 'page.display' and r.referrer_host = 'account.bbc.com', false) as is_signin_return
    from journeys j
    join in_scope i on i.visitor_id = j.visitor_id and i.signup_event = j.signup_event
    left join checkout_referrers r on r.pageview_id = j.pageview_id
    where j.event_name <> 'page.display' or j.site_id in ({{ sites }})

    union all

    select
        event_date, event_day, event_url_full, visitor_id_original, visitor_id, visit_id, pageview_id,
        connection_organisation, src_bbc_team, src_ptr_name, src_detail, src, src_organic, src_organic_detail,
        src_campaign, src_adset_name, src_medium, src_sl_term, src_creative_id, src_creation, src_campaign_type,
        src_format, content_pillar, geo_country, browser, device_type, site_id, event_name, vx_promo_code,
        billing_period, trial_duration, subscription_id, subscription_action, subscription_period_number,
        cart_turnovertaxfree, signup_event, signup_pageview_id, link_origin, signup_page, at_ptr_name,
        at_adset_name, at_creative_id, at_adset_id, at_objective, at_medium, at_bbc_team, at_matchtype,
        at_keyword, at_creation, at_campaign_name,
        link_type,
        coalesce(referrer_host = 'account.bbc.com', false) as is_signin_return   -- page views only on this branch
    from linked_events
)

select
    a.event_date, a.event_day, a.event_url_full, a.visitor_id_original, a.visitor_id, a.visit_id, a.pageview_id,
    a.connection_organisation,
    case when nullif(a.src_bbc_team, '') is not null or nullif(a.at_bbc_team, '') is not null then a.src_bbc_team
         when t.bbc_team is not null then t.bbc_team
         when lower(coalesce(a.src_ptr_name, '')) in ('facebook', 'instagram', 'fb', 'ig')
              and lower(coalesce(a.src_detail, '') || ' ' || coalesce(a.src_campaign, '')) like '%dbs^_%' escape '^' then 'dbs'
         when lower(coalesce(a.src_ptr_name, '')) in ('facebook', 'instagram', 'fb', 'ig')
              and lower(coalesce(a.src_detail, '') || ' ' || coalesce(a.src_campaign, '')) like '%8ms^_%' escape '^' then '8ms'
         else a.src_bbc_team end                                                      as src_bbc_team,
    a.src_ptr_name, a.src_detail, a.src, a.src_organic, a.src_organic_detail,
    a.src_campaign, a.src_adset_name, a.src_medium, a.src_sl_term, a.src_creative_id, a.src_creation, a.src_campaign_type,
    a.src_format, a.content_pillar, a.geo_country, a.browser, a.device_type, a.site_id, a.event_name, a.vx_promo_code,
    a.billing_period, a.trial_duration, a.subscription_id, a.subscription_action, a.subscription_period_number,
    a.cart_turnovertaxfree, a.signup_event, a.signup_pageview_id, a.link_origin, a.signup_page, a.at_ptr_name,
    a.at_adset_name, a.at_creative_id, a.at_adset_id, a.at_objective, a.at_medium, a.at_bbc_team, a.at_matchtype,
    a.at_keyword, a.at_creation, a.at_campaign_name,
    a.link_type,
    case when nullif(a.src_bbc_team, '') is not null or nullif(a.at_bbc_team, '') is not null then 'visit tag'
         when t.bbc_team is not null then 'ad id'
         when lower(coalesce(a.src_ptr_name, '')) in ('facebook', 'instagram', 'fb', 'ig')
              and lower(coalesce(a.src_detail, '') || ' ' || coalesce(a.src_campaign, '')) like any ('%dbs^_%', '%8ms^_%') escape '^' then 'campaign name'
    end                                                                               as bbc_team_source
from all_rows a
left join ad_team t
  on t.ad_id = coalesce(nullif(a.src_creative_id, ''), nullif(a.at_creative_id, ''))
 and nullif(a.src_bbc_team, '') is null and nullif(a.at_bbc_team, '') is null
qualify not a.is_signin_return
     or count_if(not a.is_signin_return) over (partition by a.visitor_id, a.signup_event) = 0
