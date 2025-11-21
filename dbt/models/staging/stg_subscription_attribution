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
  ),
    
-- Selects the relevant column and inner joins with the visitors that subscribed and looks at the events 30 days before the signup date
temp as (
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
    -- SUBSTRING(
    --        event_url_full, 
    --        POSITION('at_link_origin=' IN event_url_full) + LENGTH('at_link_origin=') , 
    --        POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_link_origin=' IN event_url_full) + LENGTH('at_link_origin=') + 1)) 
    --    ) AS link_origin,
REGEXP_SUBSTR(event_url_full, 'at_link_origin=([^&]+)', 1, 1, '', 1) AS link_origin,

-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_campaign=' IN event_url_full) + LENGTH('at_campaign='), 
--            POSITION('&' IN SUBSTRING(event_url_full, POSITION('at_campaign=' IN event_url_full) + LENGTH('at_campaign=') + 1))
--        ) AS signup_page,
REGEXP_SUBSTR(event_url_full, 'at_campaign=([^&]+)', 1, 1, '', 1) AS signup_page,

-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_ptr_name=' IN event_url_full) + LENGTH('at_ptr_name=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_ptr_name=' IN event_url_full) + LENGTH('at_ptr_name=') + 1)) 
--        ) AS at_ptr_name,
REGEXP_SUBSTR(event_url_full, 'at_ptr_name=([^&]+)', 1, 1, '', 1) AS at_ptr_name,

-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_adset_name=' IN event_url_full) + LENGTH('at_adset_name=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_adset_name=' IN event_url_full) + LENGTH('at_adset_name=') + 1)) 
--        ) AS at_adset_name,
REGEXP_SUBSTR(event_url_full, 'at_adset_name=([^&]+)', 1, 1, '', 1) AS at_adset_name,

-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_creative_id=' IN event_url_full) + LENGTH('at_creative_id=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_creative_id=' IN event_url_full) + LENGTH('at_creative_id=') + 1)) 
--        ) AS at_creative_id,
REGEXP_SUBSTR(event_url_full, 'at_creative_id=([^&]+)', 1, 1, '', 1) AS at_creative_id,

-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_adset_id=' IN event_url_full) + LENGTH('at_adset_id=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_adset_id=' IN event_url_full) + LENGTH('at_adset_id=') + 1)) 
--        ) AS at_adset_id,
REGEXP_SUBSTR(event_url_full, 'at_adset_id=([^&]+)', 1, 1, '', 1) AS at_adset_id,


-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_objective=' IN event_url_full) + LENGTH('at_objective=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_objective=' IN event_url_full) + LENGTH('at_objective=') + 1)) 
--        ) AS at_objective,
REGEXP_SUBSTR(event_url_full, 'at_objective=([^&]+)', 1, 1, '', 1) AS at_objective,

-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_medium=' IN event_url_full) + LENGTH('at_medium=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_medium=' IN event_url_full) + LENGTH('at_medium=') + 1)) 
--        ) AS at_medium,
REGEXP_SUBSTR(event_url_full, 'at_medium=([^&]+)', 1, 1, '', 1) AS at_medium,

-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_bbc_team=' IN event_url_full) + LENGTH('at_bbc_team=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_bbc_team=' IN event_url_full) + LENGTH('at_bbc_team=') + 1)) 
--        ) AS at_bbc_team,
REGEXP_SUBSTR(event_url_full, 'at_bbc_team=([^&]+)', 1, 1, '', 1) AS at_bbc_team,

-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_creation=' IN event_url_full) + LENGTH('at_creation=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_creation=' IN event_url_full) + LENGTH('at_creation=') + 1)) 
--        ) AS at_creation,
       
-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_keyword=' IN event_url_full) + LENGTH('at_keyword=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_keyword=' IN event_url_full) + LENGTH('at_keyword=') + 1)) 
--        ) AS at_keyword,
-- SUBSTRING(
--            event_url_full, 
--            POSITION('at_matchtype=' IN event_url_full) + LENGTH('at_matchtype=') , 
--            POSITION('&at' IN SUBSTRING(event_url_full, POSITION('at_matchtype=' IN event_url_full) + LENGTH('at_matchtype=') + 1)) 
--        ) AS at_matchtype,
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
),

temp2 as (
  select
    event_date, 
    event_day,
    event_url_full, 
    visitor_id,
    visit_id, 
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

    -- COALESCE(
    --   MIN(event_date) OVER (PARTITION BY visitor_id, TO_DATE(signup_event)),signup_event
    -- ) AS first_event,

    -- COALESCE(
    --   MAX(CASE WHEN event_date < signup_event THEN event_date END)
    --      OVER (PARTITION BY visitor_id, TO_DATE(signup_event)),signup_event
    -- ) AS last_event,
    
    -- Flag if event is paid
    CASE 
        WHEN COALESCE(NULLIF(src, ''),NULLIF(at_bbc_team, ''),NULLIF(at_objective, ''),NULLIF(at_ptr_name, '')) = 'paid'
            OR UPPER(src_bbc_team) IN ('8MS')
            OR UPPER(at_bbc_team) IN ('8MS', 'DBS')
            -- OR UPPER(at_objective) = 'ACQUISITION'
            OR UPPER(src_bbc_team) IN ('DBS')
        THEN 1 
        ELSE 0 
    END AS is_paid_event
from temp
),

temp_int as (

select *,
 COALESCE(MIN(event_date) OVER (PARTITION BY visitor_id, TO_DATE(signup_event)),signup_event) AS first_event,
 COALESCE(MAX(CASE WHEN event_date < signup_event and visit_number=1 THEN event_date END)OVER (PARTITION BY visitor_id, TO_DATE(signup_event)),signup_event) AS last_event,
from temp2
),

temp3 as (
select *,
case when event_date=signup_event
        or (event_date=first_event and visit_number = 1)
        or (event_date=last_event and visit_number = 1)
        or (event_date=min(event_date) over (partition by visitor_id, cast(event_date as date)) and visit_number = 1)
        or (is_paid_event = 1 and visit_number = 1)  -- First event of each paid visit
    then 'Yes'
else 'No'
end as keep_flag
from temp_int
where event_date<=signup_event
-- and visit_number != 2
qualify keep_flag='Yes'
),

temp4 as (
select *,
COUNT(*) OVER (PARTITION BY visitor_id) AS total_events,
MAX(CASE WHEN event_name = 'vx.conversion' AND vx_promo_code IS NOT NULL THEN 1 ELSE 0 END)
    OVER (PARTITION BY visitor_id) AS has_promo,
MAX(CASE WHEN event_name = 'vx.conversion' AND vx_promo_code IS NOT NULL THEN vx_promo_code ELSE NULL END)
    OVER (PARTITION BY visitor_id) AS promo_code_from_conversion,
    
-- Calculate first paid event and last paid event per visitor
MIN(CASE WHEN is_paid_event = 1 THEN event_date END) 
    OVER (PARTITION BY visitor_id) AS first_paid_event,
MAX(CASE WHEN is_paid_event = 1 THEN event_date END) 
    OVER (PARTITION BY visitor_id) AS last_paid_event,
    
-- Count total paid events
SUM(is_paid_event) OVER (PARTITION BY visitor_id) AS total_paid_events

from temp3),


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

-- CORRECTED POSITION-BASED ATTRIBUTION LOGIC WITH PROMO CODE
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
                -- CASE
                --     WHEN event_date = first_event AND event_date = first_paid_event THEN 0.3
                --     WHEN event_date = first_event THEN 0.3
                --     WHEN event_date = first_paid_event THEN 0.3
                --     WHEN event_date = last_event AND event_date = last_paid_event THEN 0.3
                --     WHEN event_date = last_event THEN 0.3
                --     WHEN event_date = last_paid_event THEN 0.3
                --     WHEN event_name = 'vx.conversion' AND vx_promo_code IS NOT NULL THEN 0.3
                --     ELSE 0.3
                -- END
            
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
                    WHEN event_date = first_event AND event_date = first_paid_event THEN 0.4  -- First event IS paid, gets full 40%
                    WHEN event_date = first_event AND first_paid_event IS NULL THEN 0.4  -- No paid events, first gets full 40%
                    WHEN event_date = first_event THEN 0.2  -- First overall event gets 20%
                    WHEN event_date = first_paid_event and first_paid_event=last_event THEN 0.4  -- First paid event gets 20%
                    WHEN event_date = first_paid_event THEN 0.2  -- First paid event gets 20%
                    
                    -- Last event bucket (40% total)
                    WHEN event_date = last_event AND event_date = last_paid_event THEN 0.4  -- Last event IS paid, gets full 40%
                    WHEN event_date = last_event AND last_paid_event IS NULL THEN 0.4  -- No paid events, last gets full 40%
                    WHEN event_date = last_event THEN 0.2  -- Last overall event gets 20%
                    WHEN event_date = last_paid_event THEN 0.2  -- Last paid event gets 20%
                    -- when event_date=first_paid_event and first_paid_event=last_event then 0.4
                    
                    -- Middle events (20% total distributed equally)
                    WHEN total_events > 3 and first_paid_event=last_event THEN 0.2 / NULLIF(total_events - 3, 0)
                    WHEN total_events > 3 and last_event != last_paid_event THEN 0.2 / NULLIF(total_events - 4, 0)
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


select 
EVENT_DATE,
EVENT_URL_FULL,
VISITOR_ID,
GEO_COUNTRY,
BROWSER,
DEVICE_TYPE,
SITE_ID,
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
src_campaign_type,
src_format,
VX_PROMO_CODE,
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
-- POSITION_WEIGHT_LAST_NON_DIRECT
FIRST_TOUCH,
LAST_TOUCH,
SIGNUP_TOUCH,
-- EVENT_NUMBER
-- EVENT_DAY
-- VISIT_ID
-- CONNECTION_ORGANISATION
-- VISIT_NUMBER
-- KEEP_FLAG
-- TOTAL_EVENTS
-- HAS_PROMO
-- FIRST_PAID_EVENT
-- LAST_PAID_EVENT
-- TOTAL_PAID_EVENTS
-- ATTRIBUTION_SRC
-- ATTRIBUTION_SRC_DETAIL
From temp5
