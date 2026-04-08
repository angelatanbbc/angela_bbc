{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='signup_event',
    on_schema_change='sync_all_columns'
) }}
    
/* ============================================================
   PURPOSE
   ------------------------------------------------------------
   1. Redistribute NULL attribution_source values proportionally
      based on existing weighted attribution.
   2. Further break down generic "Search engines" attribution
      into specific search engines using weighted redistribution.
   ============================================================ */


/* ============================================================
   STEP 1: Calculate attribution distribution for non-null sources
   ------------------------------------------------------------
   - Uses position_weight to calculate each source's share
   - Excludes Paid and NULL sources
   - These proportions will be used to reassign NULL sources
   ============================================================ */
    
WITH attribution_distribution AS (
    SELECT 
        attribution_source,
        SUM(position_weight) as total_weight,
        SUM(position_weight) / SUM(SUM(position_weight)) OVER () as proportion
    FROM {{ ref('int_subscription_attribution') }}
    WHERE attribution_source IS NOT NULL
    and attribution_source !='Paid'
    GROUP BY attribution_source
),

/* ============================================================
   STEP 2: Convert proportions into cumulative probability ranges
   ------------------------------------------------------------
   - Each attribution source occupies a probability interval
   - Used later for deterministic random assignment
   ============================================================ */
    
attribution_ranges AS (
    SELECT 
        attribution_source,
        total_weight,
        proportion,
        SUM(proportion) OVER (ORDER BY attribution_source) as cumulative_prob
    FROM attribution_distribution
),

/* ============================================================
   STEP 3: Add lower bounds for each probability range
   ------------------------------------------------------------
   - Enables BETWEEN-style joins for random assignment
   ============================================================ */
    
attribution_ranges_with_prev AS (
    SELECT 
        attribution_source,
        total_weight,
        proportion,
        cumulative_prob,
        LAG(cumulative_prob, 1, 0) OVER (ORDER BY attribution_source) as prev_cumulative_prob
    FROM attribution_ranges
),

/* ============================================================
   STEP 4: Attach a deterministic random value to each event
   ------------------------------------------------------------
   - Uses hashing to ensure reproducibility
   - Same event will always receive the same random_value
   ============================================================ */

staging_with_random AS (
    SELECT 
        *,
        -- UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) as random_value,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(VISITOR_ID, EVENT_DATE, EVENT_URL_FULL)) AS random_value

    FROM {{ ref('int_subscription_attribution') }}
    WHERE 1=1
    {% if is_incremental() %}
        AND SIGNUP_EVENT >= (SELECT DATEADD(day, -3, MAX(SIGNUP_EVENT)) FROM {{ this }})
    {% endif %}
),

/* ============================================================
   STEP 5: Replace NULL attribution_source values
   ------------------------------------------------------------
   - Join NULL records to probability ranges using random_value
   - Assign sources proportionally to observed distribution
   ============================================================ */

final as (
SELECT 
    s.EVENT_DATE,
    s.EVENT_URL_FULL,
    s.VISITOR_ID,
    s.GEO_COUNTRY,
    s.BROWSER,
    s.DEVICE_TYPE,
    s.SITE_ID,
    s.pageview_id,
    s.CONTENT_PILLAR,
    s.EVENT_NAME,
    s.SRC_DETAIL,
    s.SRC,
    -- Replace null attribution_source with proportionally assigned value using JOIN
    COALESCE(s.ATTRIBUTION_SOURCE, ar.attribution_source) as ATTRIBUTION_SOURCE,
    COALESCE(s.ATTRIBUTION_SOURCE_DETAIL, ar.attribution_source) as ATTRIBUTION_SOURCE_DETAIL,
    s.SRC_BBC_TEAM,
    s.SRC_PTR_NAME,
    s.SRC_CREATIVE_ID,
    s.SRC_ORGANIC,
    s.SRC_ORGANIC_DETAIL,
    s.SRC_CAMPAIGN,
    s.SRC_ADSET_NAME,
    s.src_campaign_type,
    s.src_format,
    s.SRC_MEDIUM,
    s.src_sl_term,
    s.VX_PROMO_CODE,
    s.billing_period,
    s.trial_duration,
    s.subscription_id,
    s.subscription_action,
    s.subscription_period_number,
    s.cart_turnovertaxfree,
    s.SIGNUP_EVENT,
    s.LINK_ORIGIN,
    s.SIGNUP_PAGE,
    s.AT_ADSET_NAME,
    s.AT_ADSET_ID,
    s.AT_OBJECTIVE,
    s.AT_MEDIUM,
    s.at_creation,
    s.at_keyword,
    s.at_matchtype,
    at_campaign_name,
    s.IS_PAID_EVENT,
    s.FIRST_EVENT,
    s.LAST_EVENT,
    s.PROMO_CODE_FROM_CONVERSION,
    s.POSITION_WEIGHT,
    s.POSITION_SIGNUP_TOUCH_WEIGHT,
    s.FIRST_TOUCH,
    s.LAST_TOUCH,
    s.SIGNUP_TOUCH
FROM staging_with_random s
LEFT JOIN attribution_ranges_with_prev ar
    ON s.random_value >= ar.prev_cumulative_prob 
    AND s.random_value < ar.cumulative_prob
    AND s.ATTRIBUTION_SOURCE IS NULL
),


/* ============================================================
   STEP 6: Build distribution for "Search engines" breakdown
   ------------------------------------------------------------
   - Only consider records already attributed to Search engines
   - Exclude the generic "Search engines" detail value
   ============================================================ */

attribution_distribution_2 AS (
    SELECT 
        attribution_source_detail,
        SUM(position_weight) as total_weight
    FROM final
    WHERE attribution_source = 'Search engines'
    AND attribution_source_detail IS NOT NULL
    AND attribution_source_detail != 'Search engines'  -- Exclude the generic value
    GROUP BY attribution_source_detail
),

/* ============================================================
   STEP 7: Convert search-engine weights into proportions
   ============================================================ */
    
attribution_with_proportion_2 AS (
    SELECT 
        attribution_source_detail,
        total_weight,
        total_weight / SUM(total_weight) OVER () as proportion
    FROM attribution_distribution_2
),

/* ============================================================
   STEP 8: Create cumulative probability ranges for search engines
   ------------------------------------------------------------
   - Ordered by weight so dominant engines get larger intervals
   ============================================================ */
    
attribution_ranges_2 AS (
    SELECT 
        attribution_source_detail,
        total_weight,
        proportion,
        SUM(proportion) OVER (ORDER BY total_weight DESC, attribution_source_detail) as cumulative_prob
    FROM attribution_with_proportion_2
),

/* ============================================================
   STEP 9: Add previous cumulative boundary for range joins
   ============================================================ */
    
attribution_ranges_with_prev_2 AS (
    SELECT 
        attribution_source_detail,
        total_weight,
        proportion,
        cumulative_prob,
        LAG(cumulative_prob, 1, 0) OVER (ORDER BY total_weight DESC, attribution_source_detail) as prev_cumulative_prob
    FROM attribution_ranges_2
),
    
/* ============================================================
   STEP 10: Assign random values to Search engine records only
   ------------------------------------------------------------
   - Non-deterministic random is acceptable here as these
     rows are already probabilistically redistributed once
   ============================================================ */

staging_with_random_2 AS (
    SELECT 
        *,
        UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS random_value
    FROM final
    WHERE attribution_source = 'Search engines'
),

/* ============================================================
   STEP 11: Replace generic "Search engines" detail values
   ------------------------------------------------------------
   - Redistribute to specific engines proportionally
   ============================================================ */
    
final_2 AS (
    SELECT 
        s.EVENT_DATE,
        s.EVENT_URL_FULL,
        s.VISITOR_ID,
        s.GEO_COUNTRY,
        s.BROWSER,
        s.DEVICE_TYPE,
        s.SITE_ID,
        s.pageview_id,
        s.CONTENT_PILLAR,
        s.EVENT_NAME,
        s.SRC_DETAIL,
        s.SRC,
        s.ATTRIBUTION_SOURCE,
        -- Replace generic "Search engines" detail with specific search engine from redistribution
        CASE 
            WHEN s.ATTRIBUTION_SOURCE_DETAIL = 'Search engines' THEN 
                COALESCE(ar.attribution_source_detail, s.ATTRIBUTION_SOURCE_DETAIL)
            ELSE s.ATTRIBUTION_SOURCE_DETAIL
        END as ATTRIBUTION_SOURCE_DETAIL,
        s.SRC_BBC_TEAM,
        s.SRC_PTR_NAME,
        s.SRC_CREATIVE_ID,
        s.SRC_ORGANIC,
        s.SRC_ORGANIC_DETAIL,
        s.SRC_CAMPAIGN,
        s.SRC_ADSET_NAME,
        s.src_campaign_type,
        s.src_format,
        s.SRC_MEDIUM,
        s.src_sl_term,
        s.VX_PROMO_CODE,
        s.billing_period,
        s.trial_duration,
        s.subscription_id,
        s.subscription_action,
        s.subscription_period_number,
        s.cart_turnovertaxfree,
        s.SIGNUP_EVENT,
        s.LINK_ORIGIN,
        s.SIGNUP_PAGE,
        s.AT_ADSET_NAME,
        s.AT_ADSET_ID,
        s.AT_OBJECTIVE,
        s.AT_MEDIUM,
        s.AT_CREATION,
        s.AT_KEYWORD,
        s.AT_MATCHTYPE,
        s.AT_CAMPAIGN_NAME,
        s.IS_PAID_EVENT,
        s.FIRST_EVENT,
        s.LAST_EVENT,
        s.PROMO_CODE_FROM_CONVERSION,
        s.POSITION_WEIGHT,
        s.POSITION_SIGNUP_TOUCH_WEIGHT,
        s.FIRST_TOUCH,
        s.LAST_TOUCH,
        s.SIGNUP_TOUCH
    FROM staging_with_random_2 s
    LEFT JOIN attribution_ranges_with_prev_2 ar
        ON s.ATTRIBUTION_SOURCE_DETAIL = 'Search engines'
        AND s.random_value >= ar.prev_cumulative_prob 
        AND s.random_value < ar.cumulative_prob
),

/* ============================================================
   FINAL OUTPUT
   ------------------------------------------------------------
   - Non-search-engine records from first redistribution
   - Search-engine records with detailed engine attribution
   ============================================================ */

setup as (select * from final where attribution_source !='Search engines'
union all
select * from final_2),

model as (select *
from setup
),

 signupevent as (SELECT
   pageview_id,
   BILLING_PERIOD,
   cart_turnovertaxfree,
   subscription_id,
   subscription_action,
   MIN(event_time) as signup_event
FROM {{ source('studios_piano', 'studios_piano_events') }}
WHERE 1=1
    AND TO_DATE(event_time) > '2025-06-25'
  -- AND site_id = 638824
  AND event_name IN ('vx.conversion')
  AND (vx_promo_code NOT IN ('BBCEMPLOYEE','BBCEDITORIAL','BBCACCOUNT','') OR vx_promo_code IS null)
  AND (app_type!='mobile-app' or app_type is null)
  {% if is_incremental() %}
        AND TO_DATE(event_time) >= (SELECT DATEADD(day, -3, MAX(signup_event)) FROM {{ this }})
    {% endif %}
  GROUP BY pageview_id, billing_period, cart_turnovertaxfree, subscription_id, subscription_action
)

select 
DATE(m.event_date) AS event_date,
-- m.event_date,
m.event_url_full,
m.visitor_id,
m.geo_country,
m.browser,
m.device_type,
m.site_id,
m.pageview_id,
m.content_pillar,
m.event_name,
m.src_detail,
m.src,
case when (m.src_format='banner'and m.src_campaign_type='owned') then 'House Ad' else m.attribution_source end as attribution_source ,
m.attribution_source_detail,
m.src_bbc_team,
m.src_ptr_name,
m.src_creative_id,
m.src_organic,
m.src_organic_detail,
m.src_campaign,
m.src_adset_name,
m.src_medium,
m.src_sl_term,
m.src_campaign_type,
m.src_format,
m.vx_promo_code,
coalesce (m.billing_period,s.billing_period) as billing_period,
m.trial_duration,
coalesce(m.subscription_id,s.subscription_id) as subscription_id,
coalesce(m.subscription_action,s.subscription_action) as subscription_action,
m.subscription_period_number,
coalesce(m.cart_turnovertaxfree,s.cart_turnovertaxfree) as cart_turnovertaxfree,
m.signup_event,
m.link_origin,
m.signup_page,
m.AT_ADSET_NAME,
m.AT_ADSET_ID,
m.AT_OBJECTIVE,
m.AT_MEDIUM,
m.AT_CREATION,
coalesce(m.src_sl_term,m.AT_KEYWORD) as AT_KEYWORD,
m.AT_MATCHTYPE,
m.AT_CAMPAIGN_NAME,
m.IS_PAID_EVENT,
m.FIRST_EVENT,
m.LAST_EVENT,
m.PROMO_CODE_FROM_CONVERSION,
m.position_weight,
m.POSITION_SIGNUP_TOUCH_WEIGHT,
m.FIRST_TOUCH,
m.LAST_TOUCH,
m.SIGNUP_TOUCH
from model m
left join signupevent s
on m.pageview_id=s.pageview_id
