{{ config(materialized="table") }}
    
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
    s.VX_PROMO_CODE,
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
    ON s.random_value BETWEEN ar.prev_cumulative_prob AND ar.cumulative_prob
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
        s.VX_PROMO_CODE,
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
)

/* ============================================================
   FINAL OUTPUT
   ------------------------------------------------------------
   - Non-search-engine records from first redistribution
   - Search-engine records with detailed engine attribution
   ============================================================ */

select * from final where attribution_source !='Search engines'
union all
select * from final_2
