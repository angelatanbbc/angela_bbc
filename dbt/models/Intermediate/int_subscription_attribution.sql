{{config(materialized="view")}}
  
/* ============================================================
   STEP 1: Normalize source fields & flag paid interactions
   ------------------------------------------------------------
   - Deduplicate events within a visit
   - Infer paid traffic using multiple source signals
   ============================================================ */
  
with temp2 as (
select
    event_date, 
    event_day,
    event_url_full, 
    visitor_id,
    visit_id, 
    pageview_id,
    signup_pageview_id,
    connection_organisation, 
    src_bbc_team, 
    src_ptr_name,
    COALESCE(NULLIF(src_detail, ''),NULLIF(at_bbc_team, ''),NULLIF(at_objective, ''),NULLIF(at_ptr_name, '')) AS src_detail,
    COALESCE(NULLIF(src, ''),NULLIF(at_bbc_team, ''),NULLIF(at_objective, ''),NULLIF(at_ptr_name, '')) AS src,
    src_organic, 
    src_organic_detail,
    src_campaign,
    src_creative_id,
    src_adset_name,
    src_medium,
    src_sl_term,
    src_creation,
    src_campaign_type,
    src_format,
    content_pillar, 
    geo_country, 
    browser, 
    device_type, 
    site_id,
    event_name,
    vx_promo_code,
    billing_period,
    trial_duration,
    subscription_id,
    subscription_action,
    subscription_period_number,
    cart_turnovertaxfree,
    signup_event,
    link_origin,
    signup_page,
    at_ptr_name,
    at_adset_name,
    at_creative_id,
    at_adset_id,
    at_objective,
    at_medium,
    at_bbc_team,
    at_creation,
    at_keyword,
    at_matchtype,
    at_campaign_name,
    row_number() over (partition by visitor_id,visit_id,event_name order by event_date ASC) as visit_number,
    -- Identify paid traffic
    CASE 
        WHEN COALESCE(NULLIF(src, ''),NULLIF(at_bbc_team, ''),NULLIF(at_objective, ''),NULLIF(at_ptr_name, '')) = 'paid'
            OR UPPER(src_bbc_team) IN ('8MS')
            OR UPPER(at_bbc_team) IN ('8MS', 'DBS')
            -- OR UPPER(at_objective) = 'ACQUISITION'
            OR UPPER(src_bbc_team) IN ('DBS')
        THEN 1 
        ELSE 0 
    END AS is_paid_event
from {{ ref('stg_subscription_attribution') }}
),

/* ============================================================
   STEP 2: Identify first and last touchpoints per signup journey
   ============================================================ */
temp_int as (
select *,
 COALESCE(MAX(CASE WHEN event_date < signup_event and visit_number=1 THEN event_date END)OVER (PARTITION BY visitor_id, signup_event),signup_event) AS last_event,
 COALESCE(MIN(event_date) OVER (PARTITION BY visitor_id, signup_pageview_id),signup_event) AS first_event,
from temp2
),

/* ============================================================
   STEP 3: Filter down to key attribution touchpoints only
   ============================================================ */
   
temp3 as (
select *,
case when event_date=signup_event
        -- or pageview_id=signup_pageview_id
        or (event_date=first_event and visit_number = 1)
        or (event_date=last_event and visit_number = 1)
        or (event_date=min(event_date) over (partition by visitor_id, cast(event_date as date)) and visit_number = 1)
        or (is_paid_event = 1 and visit_number = 1)  -- First event of each paid visit
        or (src_format='banner'and src_campaign_type='owned')
    then 'Yes'
else 'No'
end as keep_flag
from temp_int
where event_date<=signup_event
and visit_number != 2
qualify keep_flag='Yes'
),

temp3_int as (
select * exclude(first_event),
COALESCE(MIN(event_date) OVER (PARTITION BY visitor_id, signup_pageview_id),signup_event) AS first_event
from temp3
),

/* ============================================================
   STEP 4: Promo code detection
   ============================================================ */
temp4 as (
select *,
COUNT(*) OVER (PARTITION BY visitor_id,signup_event) AS total_events,
MAX(CASE WHEN event_name = 'vx.conversion' AND vx_promo_code IS NOT NULL THEN 1 ELSE 0 END)
    OVER (PARTITION BY visitor_id,signup_event) AS has_promo,
MAX(CASE WHEN event_name = 'vx.conversion' AND vx_promo_code IS NOT NULL THEN vx_promo_code ELSE NULL END)
    OVER (PARTITION BY visitor_id,signup_event) AS promo_code_from_conversion,
    
-- Calculate first paid event and last paid event per visitor
MIN(CASE WHEN is_paid_event = 1 THEN event_date END) 
    OVER (PARTITION BY visitor_id,signup_event) AS first_paid_event,
MAX(CASE WHEN is_paid_event = 1 THEN event_date END) 
    OVER (PARTITION BY visitor_id,signup_event) AS last_paid_event,
    
-- Count total paid events
SUM(is_paid_event) OVER (PARTITION BY visitor_id,signup_event) AS total_paid_events

from temp3_int),

/* ============================================================
   STEP 5: Attribution models & weighting logic
   ------------------------------------------------------------
   - Promo-aware attribution
   - Position-based weighting
   - First-touch / last-touch flags
   ============================================================ */
   
temp5 as (
select *,
CASE WHEN vx_promo_code IS NOT NULL THEN vx_promo_code || ' Promo code'ELSE src END AS Attribution_src,
CASE WHEN vx_promo_code IS NOT NULL THEN vx_promo_code || ' Promo code'ELSE src_detail END AS Attribution_src_detail,

CASE 
        WHEN total_events < 4 
             AND DATE(first_event) = DATE(last_event)
             AND promo_code_from_conversion IS NOT NULL
        THEN promo_code_from_conversion || ' Promo code'
        WHEN vx_promo_code IS NOT NULL THEN vx_promo_code || ' Promo code'ELSE src
    END AS Attribution_src_v2,

CASE 
        WHEN total_events < 4 
             AND DATE(first_event) = DATE(last_event)
             AND promo_code_from_conversion IS NOT NULL
        THEN promo_code_from_conversion || ' Promo code'
        WHEN vx_promo_code IS NOT NULL THEN vx_promo_code || ' Promo code'ELSE src_detail
END AS Attribution_src_detail_v2,

-- POSITION-BASED ATTRIBUTION LOGIC WITH PROMO CODE
CASE
    -- PROMO CODE PATH (30/30/30/10 distribution)
    WHEN has_promo = 1 THEN
        CASE
            -- Single touchpoint with promo
            WHEN total_events = 1 THEN 1.0
            
            -- Two touchpoints with promo - split 50/50
            WHEN total_events = 2 THEN 0.5
            
            -- Three touchpoints with promo (first/last paid/promo = 30% each, remaining 10%)
            WHEN total_events = 3 THEN 1/3
            
            -- 4+ touchpoints with promo
            ELSE
                CASE
                    WHEN event_date = first_event AND event_date = first_paid_event THEN 0.3
                    WHEN event_date = first_event THEN 0.3
                    WHEN event_date = first_paid_event THEN 0.3
                    WHEN event_date = last_event AND event_date = last_paid_event THEN 0.3
                    WHEN event_date = last_event THEN 0.3
                    WHEN event_date = last_paid_event THEN 0.3
                    WHEN event_name = 'vx.conversion' AND vx_promo_code IS NOT NULL THEN 0.3
                    ELSE 0.1 / NULLIF(total_events - 3, 0)
                END
        END
    
    -- NO PROMO CODE PATH (40/40/20 distribution)
    ELSE
        CASE
            -- Single touchpoint
            WHEN total_events = 1 THEN 1.0
            
            -- Two touchpoints - always split 50/50
            WHEN total_events = 2 THEN 0.5

            when total_events = 3 then 1/3
                
            -- Multiple touchpoints (3+) - Position based logic
            ELSE
                CASE
                    -- First event bucket (40% total)
                    WHEN event_date = first_event AND event_date = first_paid_event THEN 0.4  -- First event, no paid events → 0.4
                    WHEN event_date = first_event AND first_paid_event IS NULL THEN 0.4  -- First event, NOT paid → 0.2
                    WHEN event_date = first_event AND last_event = first_paid_event THEN 0.4 
                    WHEN event_date = first_event AND event_date <> first_paid_event THEN 0.2 
                    WHEN event_date = first_paid_event AND first_paid_event=last_paid_event  THEN 0.4 -- First paid event which is the only paid event gets 0.4
                    WHEN event_date = first_paid_event THEN 0.2 -- First paid event → 0.2
                    
                    -- Last event bucket (40% total)
                    WHEN event_date = last_event AND event_date = last_paid_event THEN 0.4  -- Last event IS paid, gets full 40%
                    WHEN event_date = last_event AND last_paid_event IS NULL THEN 0.4  -- No paid events, last gets full 40%\
                    WHEN event_date = last_event and last_paid_event=first_paid_event and first_event=first_paid_event THEN 0.4  -- Last event gets 40%
                    WHEN event_date = last_event and last_paid_event=first_paid_event THEN 0.2  -- Last event gets 40%
                    WHEN event_date = last_event THEN 0.2  -- Last overall event gets 20%
                    WHEN event_date = last_paid_event THEN 0.2  -- Last paid event gets 20%
                    
                    -- Middle events (20% total distributed equally)
                    WHEN total_events = 4 and last_event != last_paid_event and first_paid_event!=last_paid_event THEN 0.2
                    WHEN total_events > 3 and first_paid_event!=last_paid_event and first_paid_event=last_event and signup_event=last_paid_event THEN 0.2 / NULLIF(total_events - 3, 0)
                    WHEN total_events > 3 and first_paid_event!=last_paid_event and signup_event=last_paid_event THEN 0.2 / NULLIF(total_events - 4, 0)
                    WHEN total_events > 3 and first_paid_event!=last_paid_event and last_paid_event=last_event THEN 0.2 / NULLIF(total_events - 3, 0)
                    WHEN total_events > 3 and first_paid_event!=last_paid_event THEN 0.2 / NULLIF(total_events - 4, 0)
                    WHEN total_events > 3 and first_paid_event=last_paid_event and first_event!=first_paid_event and last_event!= last_paid_event THEN 0.2 / NULLIF(total_events - 3, 0)
                    WHEN total_events > 3 and last_event != last_paid_event THEN 0.2 / NULLIF(total_events - 2, 0)
                    WHEN total_events > 3 THEN 0.2 / NULLIF(total_events - 2, 0)
                    
                    ELSE 0
                END
        END
END AS position_weight_last_non_direct_v2,

-- Original position weight (40/40/20 split)
case when count(*) over (partition by visitor_id)=1 then 1
     when first_event=last_event then 0.5
     when event_date = first_event then 0.4 
     when event_date=signup_event then 0.4
     when count(*) over (partition by visitor_id)>2 then 0.2 / (COUNT(*) OVER (PARTITION BY visitor_id) - 2)
     else 0
end as position_weight,

-- Last non-direct (40/40/20 split on first/last/middle)
case when count(*) over (partition by visitor_id)=1 then 1
     when first_event=last_event then 0.5
     when event_date = first_event then 0.4 
     when event_date=last_event then 0.4
     when count(*) over (partition by visitor_id)>2 then 0.2 / (COUNT(*) OVER (PARTITION BY visitor_id) - 2)
     else 0
end as position_weight_last_non_direct,

case when event_date=first_event then 1 else 0 
end as first_touch,

case when event_date=last_event then 1 else 0
end as last_touch,

case when event_date=signup_event then 1 else 0
end as signup_touch,
rank() over (partition by visitor_id order by event_date) as event_number
from temp4
)

/* ============================================================
   FINAL OUTPUT: Attribution-ready event-level dataset
   ============================================================ */
select 
EVENT_DATE,
EVENT_URL_FULL,
VISITOR_ID,
GEO_COUNTRY,
BROWSER,
DEVICE_TYPE,
SITE_ID,
pageview_id,
CONTENT_PILLAR,
EVENT_NAME,
SRC_DETAIL,
SRC,
case when is_paid_event=1 then 'Paid' else ATTRIBUTION_SRC_V2 end as attribution_source,
case when is_paid_event=1 then COALESCE(SRC_BBC_TEAM,at_bbc_team) else ATTRIBUTION_SRC_DETAIL_V2 end as attribution_source_detail,
COALESCE(SRC_BBC_TEAM,at_bbc_team) as SRC_BBC_TEAM,
COALESCE(SRC_PTR_NAME,AT_PTR_NAME) as SRC_PTR_NAME,
COALESCE(SRC_CREATIVE_ID,AT_CREATIVE_ID) as SRC_CREATIVE_ID,
SRC_ORGANIC,
SRC_ORGANIC_DETAIL,
coalesce(SRC_CAMPAIGN,signup_page) as SRC_CAMPAIGN,
SRC_ADSET_NAME,
SRC_MEDIUM,
src_sl_term,
src_campaign_type,
src_format,
VX_PROMO_CODE,
billing_period,
trial_duration,
subscription_id,
subscription_action,
subscription_period_number,
cart_turnovertaxfree,
SIGNUP_EVENT,
LINK_ORIGIN,
SIGNUP_PAGE,
AT_ADSET_NAME,
AT_ADSET_ID,
AT_OBJECTIVE,
AT_MEDIUM,
COALESCE(at_creation,src_creation) as at_creation,
at_keyword,
at_matchtype,
at_campaign_name,
IS_PAID_EVENT,
FIRST_EVENT,
LAST_EVENT,
PROMO_CODE_FROM_CONVERSION,
POSITION_WEIGHT_LAST_NON_DIRECT_V2 as Position_weight,
POSITION_WEIGHT as Position_signup_touch_weight,
FIRST_TOUCH,
LAST_TOUCH,
SIGNUP_TOUCH
From temp5
