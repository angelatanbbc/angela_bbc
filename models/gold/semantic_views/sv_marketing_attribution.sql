{{
    config(
        materialized='semantic_view',
        copy_grants=true,
        static_analysis='off',
        tags=['semantic_view', 'attribution']
    )
}}

{#-
    Click based subscription attribution semantic view for Cortex Analyst and SEMANTIC_VIEW() queries.
    The body is passed straight to CREATE OR REPLACE SEMANTIC VIEW, so it follows
    Snowflake's semantic view syntax rather than the SQL style guide.

    Naming rule, as in sv_bbc_com: every dimension, fact and metric name is unique across the view.
    Dates, geography and device platform are only exposed from their dims; the fact keeps only the
    attributes of the touch itself. Dates join on the purchase date (conversion_date).
-#}

TABLES (
    -- Dimensions
    DATES AS {{ ref('dim_date') }}
        PRIMARY KEY (DATE_KEY)
        WITH SYNONYMS = ('calendar', 'days')
        COMMENT = 'Calendar dimension. One row per date. Touches join here on the date the subscription was bought, so use these columns for all date filters and groupings.',
    DEVICE_PLATFORMS AS {{ ref('dim_device_platform') }}
        PRIMARY KEY (DEVICE_PLATFORM_ID)
        WITH SYNONYMS = ('operating_system_groups', 'operating_systems', 'os', 'devices')
        COMMENT = 'Device platform of the touch: app type x device type x operating system group.',
    GEOGRAPHIES AS {{ ref('dim_geography') }}
        PRIMARY KEY (GEO_ID)
        WITH SYNONYMS = ('areas', 'locations', 'places', 'regions', 'countries')
        COMMENT = 'Country and region. One row per country and region combination seen on the facts.',
    CHANNELS AS {{ ref('dim_channel') }}
        PRIMARY KEY (CHANNEL_SK)
        WITH SYNONYMS = ('sources', 'traffic_sources', 'marketing_channels')
        COMMENT = 'Where a touch came from: the credited source, the dashboard channel group, the agency and the partner. One row per combination seen on credited touches.',
    CAMPAIGN_TAGS AS {{ ref('dim_campaign_tracking') }}
        PRIMARY KEY (CAMPAIGN_TRACKING_SK)
        WITH SYNONYMS = ('utm_tags', 'tracking_codes')
        COMMENT = 'The campaign tags a touch came in with: campaign, ad set, creative, medium and keyword. One row per set of tags.',
    ADS AS {{ ref('dim_ad') }}
        PRIMARY KEY (AD_SK)
        WITH SYNONYMS = ('creatives', 'paid_ads')
        COMMENT = 'Meta, Google Ads and Microsoft Ads ads with their names and agency. One row per ad, plus an unknown row.',

    -- Facts
    ATTRIBUTION_TOUCHPOINTS AS {{ ref('fct_attribution_touchpoints') }}
        PRIMARY KEY (ATTRIBUTION_TOUCHPOINT_SK)
        WITH SYNONYMS = ('attribution', 'credited_touchpoints', 'touchpoints', 'subscription_journeys')
        COMMENT = 'Web subscriptions with the touches in the 30 days before them that get credit. One row per credited touch, so a subscription with several touches has several rows; each credit model sums to 1 per subscription.'
)

RELATIONSHIPS (
    ATTRIBUTION_TOUCHPOINTS_TO_DATES AS ATTRIBUTION_TOUCHPOINTS (CONVERSION_DATE) REFERENCES DATES (DATE_KEY),
    ATTRIBUTION_TOUCHPOINTS_TO_DEVICE_PLATFORMS AS ATTRIBUTION_TOUCHPOINTS (DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    ATTRIBUTION_TOUCHPOINTS_TO_GEOGRAPHIES AS ATTRIBUTION_TOUCHPOINTS (GEO_ID) REFERENCES GEOGRAPHIES (GEO_ID),
    ATTRIBUTION_TOUCHPOINTS_TO_CHANNELS AS ATTRIBUTION_TOUCHPOINTS (CHANNEL_SK) REFERENCES CHANNELS (CHANNEL_SK),
    ATTRIBUTION_TOUCHPOINTS_TO_CAMPAIGN_TAGS AS ATTRIBUTION_TOUCHPOINTS (CAMPAIGN_TRACKING_SK) REFERENCES CAMPAIGN_TAGS (CAMPAIGN_TRACKING_SK),
    ATTRIBUTION_TOUCHPOINTS_TO_ADS AS ATTRIBUTION_TOUCHPOINTS (AD_SK) REFERENCES ADS (AD_SK)
)

FACTS (
    -- Attribution touchpoints
    ATTRIBUTION_TOUCHPOINTS.POSITION_WEIGHT AS position_weight
        COMMENT = 'Position based credit of the touch, the model we report. Sums to 1 per subscription.',
    ATTRIBUTION_TOUCHPOINTS.SIGNUP_TOUCH_WEIGHT AS signup_touch_weight
        COMMENT = 'Credit under the 40 / 40 / 20 model: first touch, sign up touch, the rest. Sums to 1 per subscription.',
    ATTRIBUTION_TOUCHPOINTS.FIRST_TOUCH_WEIGHT AS first_touch_weight
        COMMENT = '1 on the first touch of the journey, otherwise 0.',
    ATTRIBUTION_TOUCHPOINTS.LAST_TOUCH_WEIGHT AS last_touch_weight
        COMMENT = '1 on the last touch before the purchase, otherwise 0.'
)

DIMENSIONS (
    -- Dates
    DATES.DATE_DAY AS date_day
        WITH SYNONYMS = ('date', 'day', 'purchase_date', 'subscription_date')
        COMMENT = 'Calendar date. Touches join on the date the subscription was bought.',
    DATES.DAY_NAME AS day_name
        COMMENT = 'Full name of the day of the week, such as Monday.',
    DATES.DAYS_FROM_TODAY AS days_from_today
        COMMENT = 'Days between the date and today; positive for past dates.',
    DATES.FISCAL_QUARTER AS fiscal_quarter
        COMMENT = 'UK financial quarter, 1 to 4 (the financial year starts on 1 April).',
    DATES.FISCAL_YEAR_LABEL AS fiscal_year_label
        COMMENT = 'UK financial year label, such as 2026/27.',
    DATES.IS_CURRENT_MONTH AS is_current_month
        COMMENT = 'Whether the date is in the current month.',
    DATES.IS_CURRENT_WEEK AS is_current_week
        COMMENT = 'Whether the date is in the current week.',
    DATES.IS_CURRENT_YEAR AS is_current_year
        COMMENT = 'Whether the date is in the current calendar year.',
    DATES.IS_YESTERDAY AS is_yesterday
        COMMENT = 'Whether the date is yesterday, the latest complete day.',
    DATES.MONTH_START_DATE AS month_start_date
        COMMENT = 'First day of the month.',
    DATES.WEEK_START_DATE AS week_start_date
        WITH SYNONYMS = ('week', 'week_commencing')
        COMMENT = 'First day (Monday) of the week.',
    DATES.YEAR AS year
        COMMENT = 'Calendar year.',
    DATES.YEAR_MONTH AS year_month
        WITH SYNONYMS = ('month', 'calendar_month')
        COMMENT = 'Year and month, as YYYY-MM.',

    -- Device platforms
    DEVICE_PLATFORMS.APP_TYPE AS app_type
        WITH SYNONYMS = ('surface', 'web_or_app')
        COMMENT = 'Web or Mobile App; Other or Unknown when the event has none.',
    DEVICE_PLATFORMS.DEVICE_TYPE AS device_type
        WITH SYNONYMS = ('device')
        COMMENT = 'Device type, such as Desktop, Mobile, Tablet or Other.',
    DEVICE_PLATFORMS.OS_GROUP AS os_group
        WITH SYNONYMS = ('operating_system', 'os')
        COMMENT = 'Operating system group, such as iOS, iPadOS, Android, Windows, macOS or Chrome OS.',
    DEVICE_PLATFORMS.PLATFORM AS platform
        WITH SYNONYMS = ('device_platform')
        COMMENT = 'Reporting platform: iOS App, Android App or Other App for the mobile app; Mobile Web, Tablet Web, Desktop Web or Other Web for the web.',

    -- Geographies
    GEOGRAPHIES.GEO_COUNTRY AS geo_country
        WITH SYNONYMS = ('country', 'market')
        COMMENT = 'Country of the touch, in sentence case, such as United states, Canada or United kingdom; Unknown when not known.',
    GEOGRAPHIES.GEO_REGION AS geo_region
        WITH SYNONYMS = ('region', 'state', 'province')
        COMMENT = 'Region or state of the touch; Unknown when the event had no region.',
    GEOGRAPHIES.IS_US_OR_CANADA AS geo_country IN ('United states', 'Canada')
        WITH SYNONYMS = ('north_america')
        COMMENT = 'Whether the country is the United States or Canada, the markets where BBC.com sells subscriptions.',

    -- Channels
    CHANNELS.CHANNEL_GROUP AS channel_group
        WITH SYNONYMS = ('channel', 'source_group')
        COMMENT = 'Credited source grouped as on the attribution dashboard, such as Paid, Direct traffic, Search engines or Referrer sites.',
    CHANNELS.ATTRIBUTION_SOURCE AS attribution_source
        WITH SYNONYMS = ('source', 'traffic_source')
        COMMENT = 'Source credited for the touch: Paid, House Ad, a promo code, or Piano''s traffic source such as Direct traffic or Search engines.',
    CHANNELS.ATTRIBUTION_SOURCE_DETAIL AS attribution_source_detail
        WITH SYNONYMS = ('source_detail')
        COMMENT = 'Detail of the credited source: the agency for paid touches, otherwise the referrer, search engine or promo code.',
    CHANNELS.AGENCY AS agency
        WITH SYNONYMS = ('media_agency', 'paid_media_agency')
        COMMENT = 'Paid media agency, in lower case: 8ms or dbs. Empty for touches that are not paid media.',
    CHANNELS.PARTNER AS partner
        WITH SYNONYMS = ('publisher', 'referring_partner')
        COMMENT = 'Partner the visit came from, such as facebook, instagram or google.',

    -- Campaign tags
    CAMPAIGN_TAGS.CAMPAIGN AS campaign
        WITH SYNONYMS = ('campaign_tag')
        COMMENT = 'Campaign tag on the visit.',
    CAMPAIGN_TAGS.AD_SET_NAME AS ad_set_name
        WITH SYNONYMS = ('ad_set', 'adset')
        COMMENT = 'Ad set tag on the visit.',
    CAMPAIGN_TAGS.CREATIVE_ID AS creative_id
        WITH SYNONYMS = ('ad_id')
        COMMENT = 'Creative (ad) id tag on the visit.',
    CAMPAIGN_TAGS.MEDIUM AS medium
        COMMENT = 'Medium tag on the visit.',
    CAMPAIGN_TAGS.KEYWORD AS keyword
        WITH SYNONYMS = ('search_term')
        COMMENT = 'Paid search keyword on the visit.',

    -- Ads
    ADS.AD_PLATFORM AS platform
        WITH SYNONYMS = ('ad_network')
        COMMENT = 'Platform the ad ran on: meta, google or microsoft; unknown when the touch matched no ad.',
    ADS.AD_NAME AS ad_name
        COMMENT = 'Name of the ad as its platform reports it. For Google and Microsoft ads this is the campaign name from the agencies'' sheet.',
    ADS.PLATFORM_CAMPAIGN_NAME AS campaign_name
        WITH SYNONYMS = ('meta_campaign')
        COMMENT = 'Campaign name as Meta reports it. Empty for Google and Microsoft ads.',

    -- Attribution touchpoints
    ATTRIBUTION_TOUCHPOINTS.CONVERSION_ID AS conversion_id
        COMMENT = 'Piano identifier of the subscription purchase. Repeated on every touch of the subscription.',
    ATTRIBUTION_TOUCHPOINTS.TOUCHPOINT_DATE AS touchpoint_date
        WITH SYNONYMS = ('touch_date', 'click_date')
        COMMENT = 'Date of the touch itself. For date filters use the dates table, which joins on the purchase date.',
    ATTRIBUTION_TOUCHPOINTS.TOUCHPOINT_TYPE AS touchpoint_type
        COMMENT = 'page_view, or conversion for the purchase itself.',
    ATTRIBUTION_TOUCHPOINTS.IS_PAID_TOUCH AS is_paid_touch
        WITH SYNONYMS = ('paid', 'paid_media')
        COMMENT = 'Whether the touch came from paid media (the 8ms or dbs agency).',
    ATTRIBUTION_TOUCHPOINTS.IS_LOOKBACK_COMPLETE AS is_lookback_complete
        COMMENT = 'Whether page view history covers the full 30 days before the purchase. Purchases without it have shorter journeys and less credit for early touches.',
    ATTRIBUTION_TOUCHPOINTS.BILLING_PERIOD AS billing_period
        WITH SYNONYMS = ('plan_length', 'billing_cycle')
        COMMENT = 'Billing period of the subscription bought, such as 1 month or 1 year.',
    ATTRIBUTION_TOUCHPOINTS.IDENTITY_LINK_TYPE AS identity_link_type
        COMMENT = 'How the touch was linked to the subscriber: checkout_cookie, account (same BBC account) or device (same browser).',
    ATTRIBUTION_TOUCHPOINTS.BROWSER_GROUP AS browser_group
        WITH SYNONYMS = ('browser')
        COMMENT = 'Browser group of the touch.',
    ATTRIBUTION_TOUCHPOINTS.CONTENT_PILLAR AS content_pillar
        WITH SYNONYMS = ('pillar')
        COMMENT = 'Content pillar of the page the touch happened on.'
)

METRICS (
    -- Attribution. One row per credited touch, so subscription counts are COUNT(DISTINCT conversion_id)
    -- and credit is a SUM of a weight, which adds up to the subscription count when split.
    ATTRIBUTION_TOUCHPOINTS.SUBSCRIPTIONS AS COUNT(DISTINCT conversion_id)
        WITH SYNONYMS = ('sign_ups', 'signups', 'new_subscriptions', 'purchases', 'conversions')
        COMMENT = 'Web subscriptions with a touch in the selection.',
    ATTRIBUTION_TOUCHPOINTS.SUBSCRIPTIONS_WITH_PAID_TOUCH AS COUNT(DISTINCT IFF(is_paid_touch, conversion_id, NULL))
        WITH SYNONYMS = ('paid_touched_subscriptions')
        COMMENT = 'Web subscriptions with at least one paid touch in the selection.',
    ATTRIBUTION_TOUCHPOINTS.ATTRIBUTED_SUBSCRIPTIONS AS SUM(position_weight)
        WITH SYNONYMS = ('attributed_subs', 'credited_subscriptions', 'mta_subscriptions')
        COMMENT = 'Subscriptions credited to the touches, position based model. Split by any dimension, it adds up to the subscriptions total.',
    ATTRIBUTION_TOUCHPOINTS.PAID_ATTRIBUTED_SUBSCRIPTIONS AS SUM(IFF(is_paid_touch, position_weight, 0))
        WITH SYNONYMS = ('paid_subs', 'paid_subscribers', 'paid_subscriptions')
        COMMENT = 'Subscriptions credited to paid media touches (8ms and dbs), position based model.',
    ATTRIBUTION_TOUCHPOINTS.SIGNUP_TOUCH_ATTRIBUTED_SUBSCRIPTIONS AS SUM(signup_touch_weight)
        WITH SYNONYMS = ('signup_touch_model')
        COMMENT = 'Subscriptions credited under the 40 / 40 / 20 model (first touch, sign up touch, the rest).',
    ATTRIBUTION_TOUCHPOINTS.FIRST_TOUCH_SUBSCRIPTIONS AS SUM(first_touch_weight)
        WITH SYNONYMS = ('first_touch')
        COMMENT = 'Subscriptions credited entirely to the first touch.',
    ATTRIBUTION_TOUCHPOINTS.LAST_TOUCH_SUBSCRIPTIONS AS SUM(last_touch_weight)
        WITH SYNONYMS = ('last_touch')
        COMMENT = 'Subscriptions credited entirely to the last touch before the purchase.'
)

COMMENT = 'Click based subscription attribution: web subscriptions, the touches in the 30 days before them and their credit under four models, by channel, agency, campaign tag, ad, device, geography and content. Built by dbt (model sv_marketing_attribution).'

AI_SQL_GENERATION 'Each row of attribution_touchpoints is one credited touch of a web subscription, so never count rows: use subscriptions for the number of subscriptions and attributed_subscriptions for credit. Credit split by any dimension adds up to the subscriptions total. Paid media means the agencies 8ms and dbs: paid_attributed_subscriptions is the credit paid touches get, and subscriptions_with_paid_touch counts subscriptions with at least one paid touch. For a period such as "last week", filter dates.week_start_date, dates.year_month or dates.date_day; the dates table joins on the purchase date, and touchpoint_date is the date of the touch itself. Today is not in the dates table, so data runs to yesterday. Purchases with is_lookback_complete FALSE have less than 30 days of page view history, so their early touches are missing. Agency values are lower case (8ms, dbs). Country names are sentence case, for example ''United states'' and ''United kingdom''. App store purchases are not in this view.'

AI_VERIFIED_QUERIES (
    paid_subscriptions_by_agency_last_week AS (
        QUESTION 'How many subscriptions did each paid media agency drive last week?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS channels.agency METRICS attribution_touchpoints.paid_attributed_subscriptions, attribution_touchpoints.subscriptions_with_paid_touch WHERE attribution_touchpoints.is_paid_touch AND dates.week_start_date = DATEADD(WEEK, -1, DATE_TRUNC(WEEK, CURRENT_DATE))) ORDER BY paid_attributed_subscriptions DESC'
    ),
    credit_by_channel_last_month AS (
        QUESTION 'Which channels got the most subscription credit last month?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS channels.channel_group METRICS attribution_touchpoints.attributed_subscriptions WHERE dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY attributed_subscriptions DESC'
    ),
    paid_subscriptions_by_ad_platform_by_week AS (
        QUESTION 'How many paid subscriptions came from Meta and Google each week over the last eight weeks?'
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS dates.week_start_date, ads.ad_platform METRICS attribution_touchpoints.paid_attributed_subscriptions WHERE attribution_touchpoints.is_paid_touch AND dates.date_day >= DATEADD(WEEK, -8, DATE_TRUNC(WEEK, CURRENT_DATE))) ORDER BY week_start_date, ad_platform'
    ),
    paid_credit_by_model_last_month AS (
        QUESTION 'How much credit did paid media get last month under each attribution model?'
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS channels.agency METRICS attribution_touchpoints.attributed_subscriptions, attribution_touchpoints.signup_touch_attributed_subscriptions, attribution_touchpoints.first_touch_subscriptions, attribution_touchpoints.last_touch_subscriptions WHERE attribution_touchpoints.is_paid_touch AND dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY attributed_subscriptions DESC'
    )
)
