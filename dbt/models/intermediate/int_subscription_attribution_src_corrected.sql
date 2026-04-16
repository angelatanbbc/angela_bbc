{{config(materialized="table")}}

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
   - Always reads full table for accurate proportions
   ============================================================ */
WITH attribution_distribution AS (
    SELECT
        attribution_source,
        SUM(position_weight) as total_weight,
        SUM(position_weight) / SUM(SUM(position_weight)) OVER () as proportion
    FROM {{ ref('int_subscription_attribution') }}
    WHERE attribution_source IS NOT NULL
    AND attribution_source != 'Paid'
    GROUP BY attribution_source
),

/* ============================================================
   STEP 2: Convert proportions into cumulative probability ranges
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
   STEP 4a: Non-NULL rows pass through without range join
   ============================================================ */
non_null_rows AS (
    SELECT *
    FROM {{ ref('int_subscription_attribution') }}
    WHERE ATTRIBUTION_SOURCE IS NOT NULL
),

/* ============================================================
   STEP 4b: Only NULL rows get random value for range join
   ============================================================ */
null_rows AS (
    SELECT
        *,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(VISITOR_ID, EVENT_DATE, EVENT_URL_FULL)) AS random_value
    FROM {{ ref('int_subscription_attribution') }}
    WHERE ATTRIBUTION_SOURCE IS NULL
),

/* ============================================================
   STEP 5: Range join ONLY on the NULL subset
   ============================================================ */
null_redistributed AS (
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
        ar.attribution_source as ATTRIBUTION_SOURCE,
        ar.attribution_source as ATTRIBUTION_SOURCE_DETAIL,
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
        s.at_campaign_name,
        s.IS_PAID_EVENT,
        s.FIRST_EVENT,
        s.LAST_EVENT,
        s.PROMO_CODE_FROM_CONVERSION,
        s.POSITION_WEIGHT,
        s.POSITION_SIGNUP_TOUCH_WEIGHT,
        s.FIRST_TOUCH,
        s.LAST_TOUCH,
        s.SIGNUP_TOUCH
    FROM null_rows s
    INNER JOIN attribution_ranges_with_prev ar
        ON s.random_value >= ar.prev_cumulative_prob
        AND s.random_value < ar.cumulative_prob
),

/* ============================================================
   STEP 6: Combine NULL and non-NULL rows
   ============================================================ */
final AS (
    SELECT
        EVENT_DATE, EVENT_URL_FULL, VISITOR_ID, GEO_COUNTRY, BROWSER,
        DEVICE_TYPE, SITE_ID, pageview_id, CONTENT_PILLAR, EVENT_NAME,
        SRC_DETAIL, SRC, ATTRIBUTION_SOURCE, ATTRIBUTION_SOURCE_DETAIL,
        SRC_BBC_TEAM, SRC_PTR_NAME, SRC_CREATIVE_ID, SRC_ORGANIC,
        SRC_ORGANIC_DETAIL, SRC_CAMPAIGN, SRC_ADSET_NAME, src_campaign_type,
        src_format, SRC_MEDIUM, src_sl_term, VX_PROMO_CODE, billing_period,
        trial_duration, subscription_id, subscription_action,
        subscription_period_number, cart_turnovertaxfree, SIGNUP_EVENT,
        LINK_ORIGIN, SIGNUP_PAGE, AT_ADSET_NAME, AT_ADSET_ID, AT_OBJECTIVE,
        AT_MEDIUM, at_creation, at_keyword, at_matchtype, at_campaign_name,
        IS_PAID_EVENT, FIRST_EVENT, LAST_EVENT, PROMO_CODE_FROM_CONVERSION,
        POSITION_WEIGHT, POSITION_SIGNUP_TOUCH_WEIGHT, FIRST_TOUCH,
        LAST_TOUCH, SIGNUP_TOUCH
    FROM non_null_rows
    UNION ALL
    SELECT * FROM null_redistributed
),

/* ============================================================
   STEP 7: Build distribution for "Search engines" breakdown
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
    AND attribution_source_detail != 'Search engines'
    GROUP BY attribution_source_detail
),

/* ============================================================
   STEP 8: Convert search-engine weights into proportions
   ============================================================ */
attribution_with_proportion_2 AS (
    SELECT
        attribution_source_detail,
        total_weight,
        total_weight / SUM(total_weight) OVER () as proportion
    FROM attribution_distribution_2
),

/* ============================================================
   STEP 9: Create cumulative probability ranges for search engines
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
   STEP 10: Add previous cumulative boundary for range joins
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
   STEP 11: Split search engine rows — only generic ones need join
   ============================================================ */
search_generic_rows AS (
    SELECT
        *,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(VISITOR_ID, EVENT_DATE, EVENT_URL_FULL, ATTRIBUTION_SOURCE_DETAIL)) AS random_value
    FROM final
    WHERE attribution_source = 'Search engines'
    AND ATTRIBUTION_SOURCE_DETAIL = 'Search engines'
),

search_specific_rows AS (
    SELECT *
    FROM final
    WHERE attribution_source = 'Search engines'
    AND ATTRIBUTION_SOURCE_DETAIL != 'Search engines'
),

/* ============================================================
   STEP 12: Redistribute generic "Search engines" to specific engines
   ============================================================ */
search_redistributed AS (
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
        COALESCE(ar.attribution_source_detail, s.ATTRIBUTION_SOURCE_DETAIL) as ATTRIBUTION_SOURCE_DETAIL,
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
    FROM search_generic_rows s
    LEFT JOIN attribution_ranges_with_prev_2 ar
        ON s.random_value >= ar.prev_cumulative_prob
        AND s.random_value < ar.cumulative_prob
),

/* ============================================================
   STEP 13: Combine all three paths
   - Non-search-engine records (pass through)
   - Search engine records with specific detail (pass through)
   - Search engine records with generic detail (redistributed)
   ============================================================ */
setup AS (
    SELECT
        EVENT_DATE, EVENT_URL_FULL, VISITOR_ID, GEO_COUNTRY, BROWSER,
        DEVICE_TYPE, SITE_ID, pageview_id, CONTENT_PILLAR, EVENT_NAME,
        SRC_DETAIL, SRC, ATTRIBUTION_SOURCE, ATTRIBUTION_SOURCE_DETAIL,
        SRC_BBC_TEAM, SRC_PTR_NAME, SRC_CREATIVE_ID, SRC_ORGANIC,
        SRC_ORGANIC_DETAIL, SRC_CAMPAIGN, SRC_ADSET_NAME, src_campaign_type,
        src_format, SRC_MEDIUM, src_sl_term, VX_PROMO_CODE, billing_period,
        trial_duration, subscription_id, subscription_action,
        subscription_period_number, cart_turnovertaxfree, SIGNUP_EVENT,
        LINK_ORIGIN, SIGNUP_PAGE, AT_ADSET_NAME, AT_ADSET_ID, AT_OBJECTIVE,
        AT_MEDIUM, at_creation, at_keyword, at_matchtype, at_campaign_name,
        IS_PAID_EVENT, FIRST_EVENT, LAST_EVENT, PROMO_CODE_FROM_CONVERSION,
        POSITION_WEIGHT, POSITION_SIGNUP_TOUCH_WEIGHT, FIRST_TOUCH,
        LAST_TOUCH, SIGNUP_TOUCH
    FROM final
    WHERE attribution_source != 'Search engines'

    UNION ALL

    SELECT * FROM search_specific_rows

    UNION ALL

    SELECT * FROM search_redistributed
),

/* ============================================================
   STEP 14: Enrich with conversion event data
   ============================================================ */
signupevent AS (
    SELECT
        pageview_id,
        BILLING_PERIOD,
        cart_turnovertaxfree,
        subscription_id,
        subscription_action,
        MIN(event_time) as signup_event
    FROM {{ source('studios_piano', 'studios_piano_events') }}
    WHERE 1=1
        AND TO_DATE(event_time) > '2025-06-25'
        AND event_name IN ('vx.conversion')
        AND (vx_promo_code NOT IN ('BBCEMPLOYEE','BBCEDITORIAL','BBCACCOUNT','') OR vx_promo_code IS NULL)
        AND (app_type != 'mobile-app' OR app_type IS NULL)
    GROUP BY pageview_id, billing_period, cart_turnovertaxfree, subscription_id, subscription_action
    QUALIFY ROW_NUMBER() OVER (PARTITION BY pageview_id ORDER BY MIN(event_time) DESC) = 1
)

SELECT
    DATE(m.event_date) AS event_date,
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
    CASE
        WHEN m.src_format = 'banner' AND m.src_campaign_type = 'owned' THEN 'House Ad'
        ELSE m.attribution_source
    END AS attribution_source,
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
    COALESCE(m.billing_period, s.billing_period) AS billing_period,
    m.trial_duration,
    COALESCE(m.subscription_id, s.subscription_id) AS subscription_id,
    COALESCE(m.subscription_action, s.subscription_action) AS subscription_action,
    m.subscription_period_number,
    COALESCE(m.cart_turnovertaxfree, s.cart_turnovertaxfree) AS cart_turnovertaxfree,
    m.signup_event,
    m.link_origin,
    m.signup_page,
    m.AT_ADSET_NAME,
    m.AT_ADSET_ID,
    m.AT_OBJECTIVE,
    m.AT_MEDIUM,
    m.AT_CREATION,
    COALESCE(m.src_sl_term, m.AT_KEYWORD) AS AT_KEYWORD,
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
FROM setup m
LEFT JOIN signupevent s
    ON m.pageview_id = s.pageview_id
