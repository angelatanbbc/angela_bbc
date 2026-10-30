{{
    config(
        materialized='semantic_view',
        copy_grants=true,
        static_analysis='off',
        tags=['semantic_view', 'piano', 'subscriptions']
    )
}}

{#-
    BBC.com semantic view for Cortex Analyst and SEMANTIC_VIEW() queries.
    The body is passed straight to CREATE OR REPLACE SEMANTIC VIEW, so it follows
    Snowflake's semantic view syntax rather than the SQL style guide.

    Naming rule: every dimension, fact and metric name is unique across the view, so no
    query needs a logical-table prefix to be unambiguous. Attributes that live on a dim
    (dates, geography, device platform, experience, template, term, offer, subscription)
    are only exposed from the dim; facts keep only the attributes of their own event.
    Attributes found on more than one fact carry the fact's name as a prefix.
-#}

TABLES (
    -- Dimensions
    DATES AS {{ ref('dim_date') }}
        PRIMARY KEY (DATE_KEY)
        WITH SYNONYMS = ('calendar', 'days')
        COMMENT = 'Calendar dimension. One row per date. Every fact joins here on its event date, so use these columns for all date filters and groupings.',
    DEVICE_PLATFORMS AS {{ ref('dim_device_platform') }}
        PRIMARY KEY (DEVICE_PLATFORM_ID)
        WITH SYNONYMS = ('app', 'platform', 'operating_system_groups', 'operating_systems', 'os', 'devices')
        COMMENT = 'Device platform: app type (Web or Mobile App) x device type x operating system group. For subscription facts this is the platform of the conversion that created the subscription.',
    EXPERIENCES AS {{ ref('dim_experience') }}
        PRIMARY KEY (EXPERIENCE_ID)
        WITH SYNONYMS = ('composer_experiences', 'piano_experiences')
        COMMENT = 'Piano Composer experiences. One row per experience, with its latest state in Piano.',
    GEOGRAPHIES AS {{ ref('dim_geography') }}
        PRIMARY KEY (GEO_ID)
        WITH SYNONYMS = ('areas', 'locations', 'places', 'regions', 'countries')
        COMMENT = 'Country and region. One row per country and region combination seen on the facts.',
    OFFERS AS {{ ref('dim_offer') }}
        PRIMARY KEY (OFFER_ID)
        WITH SYNONYMS = ('piano_offers')
        COMMENT = 'Piano offers, the bundles of terms shown on a paywall or landing page. One row per offer.',
    SUBSCRIPTIONS AS {{ ref('dim_subscription') }}
        PRIMARY KEY (SUBSCRIPTION_ID)
        WITH SYNONYMS = ('subscribers')
        COMMENT = 'Paid subscriptions with their current state. One row per subscription; one user can have several subscriptions.',
    TEMPLATES AS {{ ref('dim_template') }}
        PRIMARY KEY (TEMPLATE_ID)
        WITH SYNONYMS = ('composer_templates', 'piano_templates', 'ctas')
        COMMENT = 'Piano offer templates (the CTA creative). One row per template, with a template_type classification.',
    TERMS AS {{ ref('dim_term') }}
        PRIMARY KEY (TERM_ID)
        WITH SYNONYMS = ('composer_terms', 'piano_terms', 'subscription_terms', 'vx_terms', 'plans')
        COMMENT = 'Piano terms, the plans a subscription is bought on. One row per term, with billing period, price and billing channel.',

    -- Reference
    PIANO_RETENTION_BENCHMARK AS {{ ref('piano_retention_curves') }}
        PRIMARY KEY (MONTH)
        WITH SYNONYMS = ('retention_benchmark', 'piano_benchmark', 'industry_retention')
        COMMENT = 'Piano''s benchmark retention curves across its publishers: share of subscriptions still active by months since sign-up, at the 5th to 95th percentile, for monthly and annual plans. One row per month since sign-up. Not related to the other tables; compare it with retained_subscriptions by months_since_conversion.',

    -- Facts
    CONVERSION_TOUCHPOINTS AS {{ ref('fct_conversions') }}
        WITH SYNONYMS = ('conversions', 'sign_ups')
        COMMENT = 'Subscription conversions (sign-ups), web and app. One row per conversion; paid_attribution_weight is the share of its marketing credit that went to paid media.',
    DAILY_VISITORS AS {{ ref('fct_visitors_daily') }}
        PRIMARY KEY (VISITOR_DATE_KEY)
        COMMENT = 'Daily visitors to BBC.com web and app in the United States and Canada. One row per visitor, date, site and device platform. The denominator of exposure rates.',
    EXPOSURES AS {{ ref('fct_exposures') }}
        PRIMARY KEY (EXPOSURE_ID)
        WITH SYNONYMS = ('cta_exposures', 'impressions', 'paywall_hits')
        COMMENT = 'Exposures to Piano Composer experiences (paywalls, ribbons, landing pages and other CTAs) on web and app. One row per experience.action event.',
    PAGE_VIEWS AS {{ ref('fct_page_views') }}
        PRIMARY KEY (PAGEVIEW_ID)
        WITH SYNONYMS = ('pageviews', 'traffic', 'web_traffic')
        COMMENT = 'BBC.com web page views worldwide. One row per page view. Web only: native app page views have no page view ID in Piano.',
    SUBSCRIBER_DAILY_SNAPSHOT AS {{ ref('fct_subscriber_daily_snapshot') }}
        WITH SYNONYMS = ('subscriber_daily_view', 'subscription_daily_snapshot')
        COMMENT = 'Daily subscriber state. One row per subscription per day while it is active, plus the day it churns.',
    SUBSCRIPTION_EVENTS AS {{ ref('fct_subscription_events') }}
        PRIMARY KEY (SUBSCRIPTION_ACTION_ID)
        WITH SYNONYMS = ('subscriber_events', 'subscription_lifecycle')
        COMMENT = 'Subscription lifecycle events: new subscriptions, renewals, failed renewals, cancellations, expiries and upgrades. One row per subscription action.'
)

RELATIONSHIPS (
    CONVERSION_TOUCHPOINTS_TO_DATES AS CONVERSION_TOUCHPOINTS (CONVERSION_DATE) REFERENCES DATES (DATE_KEY),
    CONVERSION_TOUCHPOINTS_TO_DEVICE_PLATFORMS AS CONVERSION_TOUCHPOINTS (DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    CONVERSION_TOUCHPOINTS_TO_EXPERIENCES AS CONVERSION_TOUCHPOINTS (EXPERIENCE_ID) REFERENCES EXPERIENCES (EXPERIENCE_ID),
    CONVERSION_TOUCHPOINTS_TO_GEOGRAPHIES AS CONVERSION_TOUCHPOINTS (GEO_ID) REFERENCES GEOGRAPHIES (GEO_ID),
    CONVERSION_TOUCHPOINTS_TO_OFFERS AS CONVERSION_TOUCHPOINTS (TERM_OFFER_ID) REFERENCES OFFERS (OFFER_ID),
    CONVERSION_TOUCHPOINTS_TO_SUBSCRIPTIONS AS CONVERSION_TOUCHPOINTS (SUBSCRIPTION_ID) REFERENCES SUBSCRIPTIONS (SUBSCRIPTION_ID),
    CONVERSION_TOUCHPOINTS_TO_TEMPLATES AS CONVERSION_TOUCHPOINTS (TEMPLATE_ID) REFERENCES TEMPLATES (TEMPLATE_ID),
    CONVERSION_TOUCHPOINTS_TO_TERMS AS CONVERSION_TOUCHPOINTS (TERM_ID) REFERENCES TERMS (TERM_ID),
    DAILY_VISITORS_TO_DATES AS DAILY_VISITORS (DATE_KEY) REFERENCES DATES (DATE_KEY),
    DAILY_VISITORS_TO_DEVICE_PLATFORMS AS DAILY_VISITORS (DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    DAILY_VISITORS_TO_GEOGRAPHIES AS DAILY_VISITORS (GEO_ID) REFERENCES GEOGRAPHIES (GEO_ID),
    EXPOSURES_TO_DATES AS EXPOSURES (EXPOSURE_DATE) REFERENCES DATES (DATE_KEY),
    EXPOSURES_TO_DEVICE_PLATFORMS AS EXPOSURES (DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    EXPOSURES_TO_EXPERIENCES AS EXPOSURES (EXPERIENCE_ID) REFERENCES EXPERIENCES (EXPERIENCE_ID),
    EXPOSURES_TO_GEOGRAPHIES AS EXPOSURES (GEO_ID) REFERENCES GEOGRAPHIES (GEO_ID),
    EXPOSURES_TO_TEMPLATES AS EXPOSURES (TEMPLATE_ID) REFERENCES TEMPLATES (TEMPLATE_ID),
    PAGE_VIEWS_TO_DATES AS PAGE_VIEWS (PAGE_VIEW_DATE) REFERENCES DATES (DATE_KEY),
    PAGE_VIEWS_TO_DEVICE_PLATFORMS AS PAGE_VIEWS (DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    PAGE_VIEWS_TO_GEOGRAPHIES AS PAGE_VIEWS (GEO_ID) REFERENCES GEOGRAPHIES (GEO_ID),
    SUBSCRIBER_DAILY_SNAPSHOT_TO_DATES AS SUBSCRIBER_DAILY_SNAPSHOT (DATE_DAY) REFERENCES DATES (DATE_KEY),
    SUBSCRIBER_DAILY_SNAPSHOT_TO_DEVICE_PLATFORMS AS SUBSCRIBER_DAILY_SNAPSHOT (CONVERSION_DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    SUBSCRIBER_DAILY_SNAPSHOT_TO_GEOGRAPHIES AS SUBSCRIBER_DAILY_SNAPSHOT (GEO_ID) REFERENCES GEOGRAPHIES (GEO_ID),
    SUBSCRIBER_DAILY_SNAPSHOT_TO_SUBSCRIPTIONS AS SUBSCRIBER_DAILY_SNAPSHOT (SUBSCRIPTION_ID) REFERENCES SUBSCRIPTIONS (SUBSCRIPTION_ID),
    SUBSCRIBER_DAILY_SNAPSHOT_TO_TERMS AS SUBSCRIBER_DAILY_SNAPSHOT (TERM_ID) REFERENCES TERMS (TERM_ID),
    SUBSCRIPTION_EVENTS_TO_DATES AS SUBSCRIPTION_EVENTS (EVENT_DATE) REFERENCES DATES (DATE_KEY),
    SUBSCRIPTION_EVENTS_TO_DEVICE_PLATFORMS AS SUBSCRIPTION_EVENTS (CONVERSION_DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    SUBSCRIPTION_EVENTS_TO_GEOGRAPHIES AS SUBSCRIPTION_EVENTS (GEO_ID) REFERENCES GEOGRAPHIES (GEO_ID),
    SUBSCRIPTION_EVENTS_TO_SUBSCRIPTIONS AS SUBSCRIPTION_EVENTS (SUBSCRIPTION_ID) REFERENCES SUBSCRIPTIONS (SUBSCRIPTION_ID),
    SUBSCRIPTION_EVENTS_TO_TERMS AS SUBSCRIPTION_EVENTS (TERM_ID) REFERENCES TERMS (TERM_ID)
)

FACTS (
    -- Conversions
    CONVERSION_TOUCHPOINTS.CART_TURNOVERTAXFREE AS cart_turnovertaxfree
        COMMENT = 'First-period revenue of the conversion excluding tax. Recorded by Piano for web checkouts; an estimate of list price less store fee for app store conversions.',
    CONVERSION_TOUCHPOINTS.PAID_ATTRIBUTION_WEIGHT AS paid_attribution_weight
        COMMENT = 'Share (0 to 1) of the conversion''s position-based marketing credit that went to paid media (DBS / 8MS) touches. 0 for app conversions and web conversions with no attribution.',
    PRIVATE CONVERSION_TOUCHPOINTS.CONVERSION_SUBSCRIPTION_WEIGHT AS subscription_weight
        COMMENT = 'Number of subscriptions the conversion counts as (2 for group plans, 10 or 25 for business plans, otherwise 1).',

    -- Subscriber daily snapshot
    SUBSCRIBER_DAILY_SNAPSHOT.MRR_AMOUNT AS mrr_amount
        COMMENT = 'Monthly recurring revenue of the subscription on the day. Zero when superseded by an upgrade.',
    PRIVATE SUBSCRIBER_DAILY_SNAPSHOT.SUBSCRIPTION_WEIGHT AS subscription_weight
        COMMENT = 'Number of subscriptions the subscription counts as (2 for group plans, 10 or 25 for business plans, otherwise 1).',

    -- Subscriptions
    SUBSCRIPTIONS.CURRENT_MRR_AMOUNT AS mrr_amount
        COMMENT = 'Monthly recurring revenue of the subscription now. Zero when ended or superseded by an upgrade.',

    -- Subscription events
    PRIVATE SUBSCRIPTION_EVENTS.CHARGED_AMOUNT
        AS IFF(subscription_action IN ('New subscription', 'Renewed', 'Upgraded subscription'), COALESCE(transaction_value, previous_transaction_value), NULL)
        COMMENT = 'Amount charged on a new subscription, renewal or upgrade, excluding tax. App store renewals carry no value from Piano, so they take the last known charge of the subscription.',
    SUBSCRIPTION_EVENTS.MRR_AFTER_EVENT AS current_mrr
        COMMENT = 'Monthly recurring revenue of the subscription after the event.',
    SUBSCRIPTION_EVENTS.MRR_BEFORE_EVENT AS previous_mrr
        COMMENT = 'Monthly recurring revenue of the subscription before the event (0 for its first event).',
    SUBSCRIPTION_EVENTS.MRR_CHANGE_AMOUNT AS mrr_change_amount
        COMMENT = 'Change in monthly recurring revenue caused by the event (mrr_after_event minus mrr_before_event).',
    SUBSCRIPTION_EVENTS.TRANSACTION_VALUE AS transaction_value
        COMMENT = 'Amount charged on the event, when the event is a charge.',

    -- Piano retention benchmark (shares from 0 to 1)
    PRIVATE PIANO_RETENTION_BENCHMARK.MONTHLY_P25 AS monthly_25,
    PRIVATE PIANO_RETENTION_BENCHMARK.MONTHLY_P50 AS monthly_50,
    PRIVATE PIANO_RETENTION_BENCHMARK.MONTHLY_P75 AS monthly_75,
    PRIVATE PIANO_RETENTION_BENCHMARK.ANNUAL_P25 AS annual_25,
    PRIVATE PIANO_RETENTION_BENCHMARK.ANNUAL_P50 AS annual_50,
    PRIVATE PIANO_RETENTION_BENCHMARK.ANNUAL_P75 AS annual_75
)

DIMENSIONS (
    -- Dates
    DATES.DATE_DAY AS date_day
        WITH SYNONYMS = ('date', 'day')
        COMMENT = 'Calendar date.',
    DATES.DAY_NAME AS day_name
        COMMENT = 'Full name of the day of the week, such as Monday.',
    DATES.DAY_NAME_SHORT AS day_name_short
        COMMENT = 'Short name of the day of the week, such as Mon.',
    DATES.DAY_OF_MONTH AS day_of_month
        COMMENT = 'Day of the month, 1 to 31.',
    DATES.DAY_OF_WEEK AS day_of_week
        COMMENT = 'Day of the week, 0 (Sunday) to 6 (Saturday).',
    DATES.DAY_OF_YEAR AS day_of_year
        COMMENT = 'Day of the year, 1 to 366.',
    DATES.DAYS_FROM_TODAY AS days_from_today
        COMMENT = 'Days between the date and today; positive for past dates.',
    DATES.FISCAL_QUARTER AS fiscal_quarter
        COMMENT = 'UK financial quarter, 1 to 4 (the financial year starts on 1 April).',
    DATES.FISCAL_YEAR AS fiscal_year
        COMMENT = 'UK financial year (1 April to 31 March), labelled by the calendar year it starts in.',
    DATES.FISCAL_YEAR_LABEL AS fiscal_year_label
        COMMENT = 'UK financial year label, such as 2026/27.',
    DATES.IS_CURRENT_MONTH AS is_current_month
        COMMENT = 'Whether the date is in the current month.',
    DATES.IS_CURRENT_QUARTER AS is_current_quarter
        COMMENT = 'Whether the date is in the current quarter.',
    DATES.IS_CURRENT_WEEK AS is_current_week
        COMMENT = 'Whether the date is in the current week.',
    DATES.IS_CURRENT_YEAR AS is_current_year
        COMMENT = 'Whether the date is in the current calendar year.',
    DATES.IS_FIRST_DAY_OF_MONTH AS is_first_day_of_month
        COMMENT = 'Whether the date is the first day of its month.',
    DATES.IS_FIRST_DAY_OF_QUARTER AS is_first_day_of_quarter
        COMMENT = 'Whether the date is the first day of its quarter.',
    DATES.IS_LAST_DAY_OF_MONTH AS is_last_day_of_month
        COMMENT = 'Whether the date is the last day of its month.',
    DATES.IS_LAST_DAY_OF_QUARTER AS is_last_day_of_quarter
        COMMENT = 'Whether the date is the last day of its quarter.',
    DATES.IS_TODAY AS is_today
        COMMENT = 'Whether the date is today. Today''s data is partial.',
    DATES.IS_WEEKDAY AS is_weekday
        COMMENT = 'Whether the date is Monday to Friday.',
    DATES.IS_WEEKEND AS is_weekend
        COMMENT = 'Whether the date is Saturday or Sunday.',
    DATES.IS_YESTERDAY AS is_yesterday
        COMMENT = 'Whether the date is yesterday, the latest complete day.',
    DATES.MONTH_END_DATE AS month_end_date
        COMMENT = 'Last day of the month.',
    DATES.MONTH_NAME AS month_name
        COMMENT = 'Full name of the month, such as October.',
    DATES.MONTH_NAME_SHORT AS month_name_short
        COMMENT = 'Short name of the month, such as Oct.',
    DATES.MONTH_OF_YEAR AS month_of_year
        COMMENT = 'Month of the year, 1 to 12.',
    DATES.MONTH_START_DATE AS month_start_date
        COMMENT = 'First day of the month.',
    DATES.QUARTER_END_DATE AS quarter_end_date
        COMMENT = 'Last day of the quarter.',
    DATES.QUARTER_NAME AS quarter_name
        COMMENT = 'Calendar quarter label, Q1 to Q4.',
    DATES.QUARTER_OF_YEAR AS quarter_of_year
        COMMENT = 'Calendar quarter of the year, 1 to 4.',
    DATES.QUARTER_START_DATE AS quarter_start_date
        COMMENT = 'First day of the quarter.',
    DATES.WEEK_END_DATE AS week_end_date
        COMMENT = 'Last day (Sunday) of the week.',
    DATES.WEEK_OF_YEAR AS week_of_year
        COMMENT = 'Week of the year, 1 to 53.',
    DATES.WEEK_START_DATE AS week_start_date
        WITH SYNONYMS = ('week', 'week_commencing')
        COMMENT = 'First day (Monday) of the week.',
    DATES.YEAR AS year
        COMMENT = 'Calendar year.',
    DATES.YEAR_END_DATE AS year_end_date
        COMMENT = 'Last day of the calendar year.',
    DATES.YEAR_MONTH AS year_month
        WITH SYNONYMS = ('month', 'calendar_month')
        COMMENT = 'Year and month, as YYYY-MM.',
    DATES.YEAR_START_DATE AS year_start_date
        COMMENT = 'First day of the calendar year.',

    -- Device platforms
    DEVICE_PLATFORMS.APP_TYPE AS app_type
        WITH SYNONYMS = ('surface', 'web_or_app')
        COMMENT = 'Web or Mobile App; Other or Unknown when the event has none.',
    DEVICE_PLATFORMS.DEVICE_TYPE AS device_type
        COMMENT = 'Device type, such as Desktop, Mobile, Tablet or Other.',
    DEVICE_PLATFORMS.OS_GROUP AS os_group
        WITH SYNONYMS = ('operating_system', 'os')
        COMMENT = 'Operating system group, such as iOS, iPadOS, Android, Windows, macOS or Chrome OS.',
    DEVICE_PLATFORMS.PLATFORM AS platform
        COMMENT = 'Reporting platform: iOS App, Android App or Other App for the mobile app; Mobile Web, Tablet Web, Desktop Web or Other Web for the web.',

    -- Experiences
    EXPERIENCES.EXPERIENCE_ID AS experience_id
        COMMENT = 'Piano identifier of the Composer experience.',
    EXPERIENCES.EXPERIENCE_NAME AS experience_name
        COMMENT = 'Name of the Composer experience in Piano.',
    EXPERIENCES.EXPERIENCE_STATUS AS experience_status
        COMMENT = 'Piano status of the experience, such as LIVE, OFFLINE, SCHEDULED or ARCHIVED.',
    EXPERIENCES.EXPERIENCE_TYPE AS experience_type
        COMMENT = 'Piano experience type: site, mobile or template-interaction.',
    EXPERIENCES.IS_APP_EXPERIENCE AS is_app_experience
        COMMENT = 'Whether the experience runs in the mobile app (TRUE) or on the web (FALSE).',

    -- Geographies
    GEOGRAPHIES.GEO_COUNTRY AS geo_country
        WITH SYNONYMS = ('country')
        COMMENT = 'Country, in sentence case, such as United states, Canada or United kingdom; Unknown when not known.',
    GEOGRAPHIES.GEO_REGION AS geo_region
        WITH SYNONYMS = ('region', 'state', 'province')
        COMMENT = 'Region or state; Unknown when the event had no region.',
    GEOGRAPHIES.IS_US_OR_CANADA AS geo_country IN ('United states', 'Canada')
        WITH SYNONYMS = ('north_america')
        COMMENT = 'Whether the tracked country is the United States or Canada, the scope of daily_visitors. For subscription metrics filter on subscription_country instead: geo tracking is often Unknown, and every subscription is sold in one of the two.',

    -- Offers
    OFFERS.OFFER_ID AS offer_id
        COMMENT = 'Piano identifier of the offer.',
    OFFERS.OFFER_NAME AS offer_name
        COMMENT = 'Name of the Piano offer the term was bought through.',
    OFFERS.OFFER_STATUS AS offer_status
        COMMENT = 'Piano status of the offer.',

    -- Subscriptions
    SUBSCRIPTIONS.COHORT_MONTH AS cohort_month
        WITH SYNONYMS = ('acquisition_month', 'signup_month')
        COMMENT = 'Month the subscription was bought, as YYYY-MM.',
    SUBSCRIPTIONS.CONVERSION_PAYMENT_PROVIDER AS conversion_payment_provider
        COMMENT = 'Payment provider of the conversion that created the subscription: Stripe Elements or Braintree Credit Card for web checkouts, Apple App Store or Google Play for app stores.',
    SUBSCRIPTIONS.CREATED_VIA_UPGRADE AS created_via_upgrade
        COMMENT = 'Whether the subscription was created by an upgrade.',
    SUBSCRIPTIONS.IS_CURRENTLY_ACTIVE AS is_active
        COMMENT = 'Whether the subscription is active now. For status on a past date use subscriber_status.',
    SUBSCRIPTIONS.IS_SUBSCRIPTION_COUNTRY_ESTIMATED AS is_subscription_country_estimated
        COMMENT = 'Whether subscription_country is estimated from geo tracking (app store subscriptions) rather than taken from the term (web checkout).',
    SUBSCRIPTIONS.IS_ENDED_BY_UPGRADE AS is_ended_by_upgrade
        COMMENT = 'Whether the subscription ended because the user upgraded.',
    SUBSCRIPTIONS.LATEST_ACTION AS latest_action
        COMMENT = 'Latest subscription action now, such as Renewed, Expired, Canceled or Auto-renew disabled.',
    SUBSCRIPTIONS.LATEST_ACTION_AT AS latest_action_at
        COMMENT = 'Date and time of the latest subscription action.',
    SUBSCRIPTIONS.LATEST_SUBSCRIPTION_PERIOD_NUMBER AS subscription_period_number
        COMMENT = 'Latest billing period number of the subscription (1 for the first period).',
    SUBSCRIPTIONS.NEXT_BILLING_DATE AS next_billing_at::DATE
        WITH SYNONYMS = ('renewal_date', 'next_bill_date', 'paid_through_date')
        COMMENT = 'Date the current paid period ends: the next renewal charge, or the expiry date when auto-renew is off. Null once the subscription has ended.',
    SUBSCRIPTIONS.SUBSCRIPTION_COUNTRY AS subscription_country
        WITH SYNONYMS = ('market', 'subscriber_country')
        COMMENT = 'Country the subscription was bought in: United states or Canada. From the term for web checkouts; estimated from geo tracking for app store subscriptions, defaulting to United states. Use this, not geo_country, to filter or group subscription metrics by market.',
    SUBSCRIPTIONS.SUBSCRIPTION_END_TYPE AS subscription_end_type
        COMMENT = 'How the subscription ended: Expired, Canceled, Renewal failed, will not retry, Upgraded or Unknown; null while active.',
    SUBSCRIPTIONS.SUBSCRIPTION_ENDED_AT AS subscription_ended_at
        COMMENT = 'Date and time the subscription ended.',
    SUBSCRIPTIONS.SUBSCRIPTION_ID AS subscription_id
        COMMENT = 'Piano identifier of the subscription.',
    SUBSCRIPTIONS.SUBSCRIPTION_SEQUENCE_NUMBER AS subscription_sequence_number
        COMMENT = 'Order of the subscription within the user''s subscription history (1 for their first).',
    SUBSCRIPTIONS.SUBSCRIPTION_START_TYPE AS subscription_start_type
        COMMENT = 'How the subscription began: Brand New, Re-subscription or Upgrade.',
    SUBSCRIPTIONS.SUBSCRIPTION_STARTED_AT AS subscription_started_at
        COMMENT = 'Date and time the subscription started.',
    SUBSCRIPTIONS.USER_FIRST_PARTY_ID AS user_first_party_id
        COMMENT = 'First-party (FED) identifier of the subscriber.',

    -- Templates
    TEMPLATES.TEMPLATE_ID AS template_id
        COMMENT = 'Piano identifier of the offer template.',
    TEMPLATES.TEMPLATE_NAME AS template_name
        COMMENT = 'Name of the offer template in Piano.',
    TEMPLATES.TEMPLATE_STATUS AS template_status
        COMMENT = 'Piano status of the template: active or archived.',
    TEMPLATES.TEMPLATE_TYPE AS template_type
        WITH SYNONYMS = ('cta_type')
        COMMENT = 'CTA type of the template: Paywall, Ribbon, Subscription Landing Page or Other.',

    -- Terms
    TERMS.BILLING_CHANNEL AS billing_channel
        COMMENT = 'Where subscriptions on the term are billed: Web checkout, Apple App Store or Google Play.',
    TERMS.TERM_BILLING_COUNTRY AS billing_country
        COMMENT = 'Country a web checkout term is sold in, from its currency: United states (USD) or Canada (CAD). Null for app store terms, which cover both.',
    TERMS.BILLING_PERIOD AS billing_period
        WITH SYNONYMS = ('plan_length', 'monthly_or_annual')
        COMMENT = 'Renewal period of the term, such as 1 month or 1 year.',
    TERMS.CURRENCY_CODE AS currency_code
        COMMENT = 'Currency of the term''s prices.',
    TERMS.HAS_FREE_TRIAL AS has_free_trial
        COMMENT = 'Whether the term has a free trial.',
    TERMS.TERM_ID AS term_id
        COMMENT = 'Piano identifier of the term.',
    TERMS.TERM_NAME AS term_name
        WITH SYNONYMS = ('plan', 'plan_name')
        COMMENT = 'Name of the term (plan), such as The Annual Plan or The Monthly Plan - iOS.',
    TERMS.TERM_TYPE AS term_type
        COMMENT = 'Piano term type, such as payment or external (app store).',

    -- Conversions
    CONVERSION_TOUCHPOINTS.CONVERSION_AB_TEST_VARIANT_NAME AS ab_test_variant_name
        COMMENT = 'A/B test variant of the experience that led to the conversion.',
    CONVERSION_TOUCHPOINTS.CONVERSION_C1X_CONTENT_LIKELY_TO_CONVERT AS c1x_content_likely_to_convert
        COMMENT = 'C1X Content Likely to Convert score bucket of the content viewed at conversion.',
    CONVERSION_TOUCHPOINTS.CONVERSION_C1X_LIKELIHOOD_TO_REGISTER AS c1x_likelihood_to_register
        COMMENT = 'C1X Likelihood to Register score bucket of the visitor at conversion.',
    CONVERSION_TOUCHPOINTS.CONVERSION_C1X_LIKELIHOOD_TO_RETURN AS c1x_likelihood_to_return
        COMMENT = 'C1X Likelihood to Return score bucket of the visitor at conversion.',
    CONVERSION_TOUCHPOINTS.CONVERSION_C1X_LTS AS c1x_lts
        COMMENT = 'C1X Likelihood to Subscribe (LtS) score bucket of the visitor at conversion.',
    CONVERSION_TOUCHPOINTS.CONVERSION_C1X_REVENUE_AUTO_OPTIMIZATION AS c1x_revenue_auto_optimization
        COMMENT = 'C1X Revenue Optimization score bucket of the page view at conversion.',
    CONVERSION_TOUCHPOINTS.CONVERSION_CARD_ACTION AS card_action
        COMMENT = 'Action of the Composer card that led to the conversion, such as showOffer or showTemplate.',
    CONVERSION_TOUCHPOINTS.CONVERSION_CARD_ID AS card_id
        COMMENT = 'Identifier of the Composer card that led to the conversion.',
    CONVERSION_TOUCHPOINTS.CONVERSION_ID AS conversion_id
        COMMENT = 'Piano identifier of the conversion.',
    CONVERSION_TOUCHPOINTS.CONVERSION_TIME AS conversion_time
        COMMENT = 'Date and time of the conversion.',
    CONVERSION_TOUCHPOINTS.PAYMENT_PROVIDER AS payment_provider
        COMMENT = 'Payment provider observed on the conversion: Stripe Elements or Braintree Credit Card for web checkouts, Apple App Store or Google Play for app stores.',
    CONVERSION_TOUCHPOINTS.CONVERSION_SRC AS src
        COMMENT = 'Piano traffic source of the conversion visit, such as Direct traffic, Search engines or BBC Public Service sites. For the full marketing journey use sv_marketing_attribution.',
    CONVERSION_TOUCHPOINTS.CONVERSION_SRC_DETAIL AS src_detail
        COMMENT = 'Detailed Piano traffic source of the conversion visit, such as a search engine or campaign name.',
    CONVERSION_TOUCHPOINTS.CONVERSION_VISIT_TIME AS visit_time
        COMMENT = 'Date and time the conversion visit started.',
    CONVERSION_TOUCHPOINTS.VX_PROMO_CODE AS vx_promo_code
        WITH SYNONYMS = ('promo_code')
        COMMENT = 'Promo code used at conversion, if any.',

    -- Exposures
    EXPOSURES.AB_TEST_CARD_TITLE AS ab_test_card_title
        COMMENT = 'Title of the A/B test card shown.',
    EXPOSURES.AB_TEST_VARIANT_NAME AS ab_test_variant_name
        COMMENT = 'A/B test variant of the experience shown.',
    EXPOSURES.C1X_CONTENT_LIKELY_TO_CONVERT AS c1x_content_likely_to_convert
        COMMENT = 'C1X Content Likely to Convert score bucket of the content at exposure.',
    EXPOSURES.C1X_LIKELIHOOD_TO_REGISTER AS c1x_likelihood_to_register
        COMMENT = 'C1X Likelihood to Register score bucket of the visitor at exposure.',
    EXPOSURES.C1X_LIKELIHOOD_TO_RETURN AS c1x_likelihood_to_return
        COMMENT = 'C1X Likelihood to Return score bucket of the visitor at exposure.',
    EXPOSURES.C1X_LTS AS c1x_lts
        COMMENT = 'C1X Likelihood to Subscribe (LtS) score bucket of the visitor at exposure.',
    EXPOSURES.C1X_REVENUE_AUTO_OPTIMIZATION AS c1x_revenue_auto_optimization
        COMMENT = 'C1X Revenue Optimization score bucket of the page view at exposure.',
    EXPOSURES.CARD_ACTION AS card_action
        COMMENT = 'Action of the Composer card shown, such as showOffer or showTemplate.',
    EXPOSURES.CARD_ID AS card_id
        COMMENT = 'Identifier of the Composer card shown.',
    EXPOSURES.CARD_NAME AS card_name
        COMMENT = 'Name of the Composer card shown.',
    EXPOSURES.EXPOSURE_CONTENT_ID AS content_id
        COMMENT = 'Identifier (URN) of the content the exposure happened on.',
    EXPOSURES.EXPOSURE_CONTENT_PILLAR AS content_pillar
        COMMENT = 'Editorial pillar of the content the exposure happened on, when available.',
    EXPOSURES.EXPOSURE_CONTENT_SECTION AS content_section
        COMMENT = 'Editorial section of the content the exposure happened on, when available.',
    EXPOSURES.EXPOSURE_CONTENT_TOPIC AS content_topic
        COMMENT = 'Editorial topic of the content the exposure happened on, when available.',
    EXPOSURES.EXPOSURE_CONTENT_TYPE AS content_type
        COMMENT = 'Piano content type of the page the exposure happened on, when available.',
    EXPOSURES.EXPOSURE_PAGE AS page
        COMMENT = 'Piano page name the exposure happened on, such as home.page.',
    EXPOSURES.EXPOSURE_PAGE_CONTENT_TYPE AS page_content_type
        COMMENT = 'Content type of the page the exposure happened on, such as video, indexPage or audio-episode.',
    EXPOSURES.EXPOSURE_PAGE_TITLE AS page_title
        COMMENT = 'Title of the page the exposure happened on.',
    EXPOSURES.EXPOSURE_TIME AS exposure_time
        COMMENT = 'Date and time of the exposure.',
    EXPOSURES.EXPOSURE_URL AS url
        COMMENT = 'URL of the page the exposure happened on.',

    -- Page views
    PAGE_VIEWS.APP_NAME AS app_name
        COMMENT = 'Piano application or property name, such as bbc_web.',
    PAGE_VIEWS.BROWSER_GROUP AS browser_group
        WITH SYNONYMS = ('browser')
        COMMENT = 'Browser family, such as Chrome or Safari; Unknown when blank.',
    PAGE_VIEWS.CONTENT_PILLAR AS content_pillar
        WITH SYNONYMS = ('pillar')
        COMMENT = 'Editorial pillar of the page viewed.',
    PAGE_VIEWS.CONTENT_SECTION AS content_section
        WITH SYNONYMS = ('section')
        COMMENT = 'Editorial section of the page viewed.',
    PAGE_VIEWS.CONTENT_TYPE AS content_type
        COMMENT = 'Content type of the page viewed, such as article or video.',
    PAGE_VIEWS.PAGE AS page
        COMMENT = 'Piano page name of the page viewed, such as home.page.',
    PAGE_VIEWS.PAGE_VIEW_TIME AS page_view_time
        COMMENT = 'Date and time of the page view (local time).',
    PAGE_VIEWS.SITE_ID AS site_id
        COMMENT = 'Piano site of the page view.',
    PAGE_VIEWS.SRC AS src
        WITH SYNONYMS = ('traffic_source', 'referrer_type')
        COMMENT = 'Piano traffic source of the visit, such as Direct traffic, Search engines or Social media.',
    PAGE_VIEWS.SRC_CAMPAIGN AS src_campaign
        COMMENT = 'Piano campaign of the visit, when it came from a tagged campaign.',
    PAGE_VIEWS.SRC_DETAIL AS src_detail
        WITH SYNONYMS = ('traffic_source_detail', 'referrer')
        COMMENT = 'Detailed Piano traffic source of the visit, such as a search engine, site or campaign name.',
    PAGE_VIEWS.URL AS url
        COMMENT = 'URL of the page viewed.',
    PAGE_VIEWS.VISITOR_NEW_RETURN AS visitor_new_return
        WITH SYNONYMS = ('new_or_returning')
        COMMENT = 'Whether the visitor was New or Returning at the time of the page view.',

    -- Piano retention benchmark
    PIANO_RETENTION_BENCHMARK.BENCHMARK_MONTH AS month
        COMMENT = 'Months since sign-up on the Piano benchmark curve, 0 to 59. Matches months_since_conversion.',

    -- Subscriber daily snapshot
    SUBSCRIBER_DAILY_SNAPSHOT.DAYS_SINCE_CHURNED AS days_since_churned
        COMMENT = 'Days since the subscription churned (0 on the churn day).',
    SUBSCRIBER_DAILY_SNAPSHOT.DAYS_SINCE_CONVERSION AS days_since_conversion
        WITH SYNONYMS = ('tenure_days')
        COMMENT = 'Days between the conversion and the snapshot date.',
    SUBSCRIBER_DAILY_SNAPSHOT.LAST_SUBSCRIPTION_ACTION AS last_subscription_action
        COMMENT = 'Latest subscription action on or before the snapshot date.',
    SUBSCRIBER_DAILY_SNAPSHOT.MONTHS_SINCE_CONVERSION AS months_since_conversion
        WITH SYNONYMS = ('tenure_months')
        COMMENT = 'Months between the conversion and the snapshot date.',
    SUBSCRIBER_DAILY_SNAPSHOT.SNAPSHOT_DATE AS date_day
        COMMENT = 'Snapshot date. Prefer date_day from dates for filtering and grouping.',
    SUBSCRIBER_DAILY_SNAPSHOT.SNAPSHOT_SUBSCRIPTION_PERIOD_NUMBER AS subscription_period_number
        COMMENT = 'Billing period number of the subscription on the snapshot date.',
    SUBSCRIBER_DAILY_SNAPSHOT.SUBSCRIBER_STATUS AS subscriber_status
        COMMENT = 'Active or Churned on the snapshot date.',

    -- Subscription events
    SUBSCRIPTION_EVENTS.EVENT_SUBSCRIPTION_PERIOD_NUMBER AS subscription_period_number
        COMMENT = 'Billing period number of the subscription at the event; a Renewed event with 2 is the first renewal.',
    SUBSCRIPTION_EVENTS.EVENT_TIME AS event_time
        COMMENT = 'Date and time of the subscription event.',
    SUBSCRIPTION_EVENTS.SUBSCRIPTION_ACTION AS subscription_action
        WITH SYNONYMS = ('event_type', 'lifecycle_event')
        COMMENT = 'Type of subscription event: New subscription, Renewed, Renewal failed, will retry, Renewal failed, will not retry, Auto-renew disabled, Auto-renew enabled, Expired, Canceled, or an upgrade event.'
)

METRICS (
    -- Conversions. fct_conversions has one row per conversion; paid and organic sign-ups split each
    -- conversion by its paid_attribution_weight, so they add up to conversions.
    CONVERSION_TOUCHPOINTS.CONVERSIONS AS COUNT(conversion_id)
        WITH SYNONYMS = ('new_starts', 'new_subscriptions', 'sign_ups', 'signups', 'subscription_starts', 'acquisitions')
        COMMENT = 'New subscription sign-ups.',
    CONVERSION_TOUCHPOINTS.PAID_CONVERSIONS AS SUM(paid_attribution_weight)
        WITH SYNONYMS = ('paid_signups', 'paid_media_signups')
        COMMENT = 'Sign-ups credited to paid media (DBS / 8MS), with fractional multi-touch attribution: a conversion counts by the share of its credit that went to paid touches. Paid plus organic sign-ups equals conversions. For channel-level attribution use sv_marketing_attribution.',
    CONVERSION_TOUCHPOINTS.ORGANIC_CONVERSIONS AS SUM(1 - paid_attribution_weight)
        WITH SYNONYMS = ('organic_signups', 'unpaid_signups')
        COMMENT = 'Sign-ups not credited to paid media: conversions minus paid_conversions. App conversions count as organic.',
    CONVERSION_TOUCHPOINTS.CONVERSIONS_LANDING_PAGE AS SUM(IFF(templates.template_type = 'Subscription Landing Page', 1, 0))
        COMMENT = 'Sign-ups from the Subscription Landing Page template type.',
    CONVERSION_TOUCHPOINTS.CONVERSIONS_PAYWALL AS SUM(IFF(templates.template_type = 'Paywall', 1, 0))
        COMMENT = 'Sign-ups from the Paywall template type.',
    CONVERSION_TOUCHPOINTS.CONVERSIONS_RIBBON AS SUM(IFF(templates.template_type = 'Ribbon', 1, 0))
        COMMENT = 'Sign-ups from the Ribbon template type.',
    CONVERSION_TOUCHPOINTS.WEIGHTED_CONVERSIONS AS SUM(conversion_touchpoints.conversion_subscription_weight)
        COMMENT = 'Sign-ups counting group and business plans as the number of subscriptions they include (2, 10 or 25).',
    CONVERSION_TOUCHPOINTS.CONVERSION_REVENUE AS SUM(cart_turnovertaxfree)
        WITH SYNONYMS = ('acquisition_revenue', 'first_period_revenue')
        COMMENT = 'First-period revenue of sign-ups excluding tax. App store revenue is an estimate of list price less store fee.',

    -- Exposures
    EXPOSURES.EXPOSURE_EVENTS AS COUNT(exposure_id)
        WITH SYNONYMS = ('exposure_count', 'cta_impressions')
        COMMENT = 'Number of exposure events (times a CTA was shown).',
    EXPOSURES.EXPOSED_VISITORS AS COUNT(DISTINCT visitor_id)
        COMMENT = 'Distinct visitors exposed to any Composer experience. Not reliable for the mobile app, where visitor_id is not stable across exposures.',
    EXPOSURES.EXPOSED_VISITORS_LANDING_PAGE AS COUNT(DISTINCT IFF(templates.template_type = 'Subscription Landing Page', visitor_id, NULL))
        WITH SYNONYMS = ('exposed_visitors_subscription_landing_page', 'exposures_landing_page', 'exposures_subscription_landing_page')
        COMMENT = 'Distinct visitors exposed to a Subscription Landing Page template.',
    EXPOSURES.EXPOSED_VISITORS_PAYWALL AS COUNT(DISTINCT IFF(templates.template_type = 'Paywall', visitor_id, NULL))
        WITH SYNONYMS = ('paywall_displays', 'paywall_exposures', 'paywall_views')
        COMMENT = 'Distinct visitors exposed to a Paywall template.',
    PRIVATE EXPOSURES.EXPOSED_VISITORS_PAYWALL_US_CANADA AS COUNT(DISTINCT IFF(templates.template_type = 'Paywall' AND geographies.geo_country IN ('United states', 'Canada'), visitor_id, NULL))
        COMMENT = 'Distinct US and Canada visitors exposed to a Paywall template; numerator of exposure_rate_paywall.',
    EXPOSURES.EXPOSED_VISITORS_RIBBON AS COUNT(DISTINCT IFF(templates.template_type = 'Ribbon', visitor_id, NULL))
        WITH SYNONYMS = ('ribbon_displays', 'ribbon_exposures', 'ribbon_hits', 'ribbon_views')
        COMMENT = 'Distinct visitors exposed to a Ribbon template.',
    PRIVATE EXPOSURES.EXPOSED_VISITORS_RIBBON_US_CANADA AS COUNT(DISTINCT IFF(templates.template_type = 'Ribbon' AND geographies.geo_country IN ('United states', 'Canada'), visitor_id, NULL))
        COMMENT = 'Distinct US and Canada visitors exposed to a Ribbon template; numerator of exposure_rate_ribbon.',
    PRIVATE EXPOSURES.EXPOSED_VISITORS_LANDING_PAGE_US_CANADA AS COUNT(DISTINCT IFF(templates.template_type = 'Subscription Landing Page' AND geographies.geo_country IN ('United states', 'Canada'), visitor_id, NULL))
        COMMENT = 'Distinct US and Canada visitors exposed to a Subscription Landing Page template; numerator of exposure_rate_landing_page.',

    -- Daily visitors (US and Canada, web and app)
    DAILY_VISITORS.DISTINCT_VISITORS AS COUNT(DISTINCT visitor_id)
        WITH SYNONYMS = ('visitors', 'audience', 'unique_visitors', 'us_canada_visitors')
        COMMENT = 'Distinct visitors to BBC.com web and app in the United States and Canada. The exposure-rate denominator, as in the acquisition dashboard. For worldwide web visitors use page_view_visitors.',

    -- Page views (web, worldwide)
    PAGE_VIEWS.PAGEVIEWS AS SUM(page_display_event_count)
        WITH SYNONYMS = ('page_view_count', 'pvs', 'page_impressions')
        COMMENT = 'Web page views, as Piano counts them (page.display events).',
    PAGE_VIEWS.PAGE_VIEW_VISITORS AS COUNT(DISTINCT visitor_id)
        WITH SYNONYMS = ('web_visitors', 'unique_browsers')
        COMMENT = 'Distinct web visitors (browsers) with at least one page view, worldwide.',
    PAGE_VIEWS.PAGE_VIEW_VISITS AS COUNT(DISTINCT visit_id)
        WITH SYNONYMS = ('visits', 'sessions')
        COMMENT = 'Distinct web visits (sessions) with at least one page view.',
    PAGE_VIEWS.LOGGED_IN_USERS AS COUNT(DISTINCT user_id)
        WITH SYNONYMS = ('signed_in_users', 'registered_users')
        COMMENT = 'Distinct registered users who viewed a page while logged in.',
    PAGE_VIEWS.TIME_SPENT_SECONDS AS SUM(event_duration_ms) / 1000
        WITH SYNONYMS = ('total_time_spent', 'engagement_time')
        COMMENT = 'Total time spent on web pages, in seconds (Piano event durations).',
    PAGE_VIEWS.TIME_SPENT_PER_VISITOR_SECONDS AS SUM(event_duration_ms) / 1000 / NULLIFZERO(COUNT(DISTINCT IFF(event_duration_ms > 0, visitor_id, NULL)))
        WITH SYNONYMS = ('average_time_spent', 'time_per_visitor', 'dwell_time')
        COMMENT = 'Average time spent per visitor in seconds, Piano''s Time Spent / Visitor: total time spent divided by visitors with any time spent.',
    PAGE_VIEWS.AVERAGE_SCROLL_DEPTH_PCT AS AVG(NULLIF(scroll_depth_pct, 0))
        WITH SYNONYMS = ('scroll_depth')
        COMMENT = 'Average maximum scroll depth (0-100) of page views that sent a scroll event.',
    PAGE_VIEWS.CLICKS AS SUM(click_count)
        COMMENT = 'Click events on web pages (navigation, action, exit, campaign, ad and search result clicks).',
    PAGE_VIEWS.AD_IMPRESSIONS AS SUM(ad_impression_count)
        COMMENT = 'Ad impressions on web pages.',
    PAGE_VIEWS.PAGEVIEWS_PER_VISIT AS SUM(page_display_event_count) / NULLIFZERO(COUNT(DISTINCT visit_id))
        WITH SYNONYMS = ('pages_per_session', 'depth_of_visit')
        COMMENT = 'Average page views per web visit.',
    PAGE_VIEWS.PAGEVIEWS_PER_VISITOR AS SUM(page_display_event_count) / NULLIFZERO(COUNT(DISTINCT visitor_id))
        COMMENT = 'Average page views per web visitor.',

    -- Subscribers. Stock metrics take the last (or first) day of the period instead of summing days.
    SUBSCRIBER_DAILY_SNAPSHOT.ACTIVE_SUBSCRIBERS
        NON ADDITIVE BY (SUBSCRIBER_DAILY_SNAPSHOT.SNAPSHOT_DATE ASC NULLS LAST)
        AS COUNT(DISTINCT IFF(subscriber_status = 'Active', subscription_id, NULL))
        WITH SYNONYMS = ('active_subs', 'live_subs', 'paying_subs', 'paying_subscribers', 'subscribers', 'subscriber_base', 'closing_subscribers')
        COMMENT = 'Active paid subscriptions at the end of the selected period.',
    SUBSCRIBER_DAILY_SNAPSHOT.OPENING_ACTIVE_SUBSCRIBERS
        NON ADDITIVE BY (SUBSCRIBER_DAILY_SNAPSHOT.SNAPSHOT_DATE DESC NULLS LAST)
        AS COUNT(DISTINCT IFF(subscriber_status = 'Active', subscription_id, NULL))
        COMMENT = 'Active paid subscriptions at the beginning of the selected period.',
    SUBSCRIBER_DAILY_SNAPSHOT.WEIGHTED_ACTIVE_SUBSCRIBERS
        NON ADDITIVE BY (SUBSCRIBER_DAILY_SNAPSHOT.SNAPSHOT_DATE ASC NULLS LAST)
        AS SUM(IFF(subscriber_status = 'Active', subscriber_daily_snapshot.subscription_weight, 0))
        COMMENT = 'Active subscriptions at the end of the period, counting group and business plans as the number of subscriptions they include (2, 10 or 25).',
    SUBSCRIBER_DAILY_SNAPSHOT.MRR
        NON ADDITIVE BY (SUBSCRIBER_DAILY_SNAPSHOT.SNAPSHOT_DATE ASC NULLS LAST)
        AS SUM(mrr_amount)
        WITH SYNONYMS = ('monthly_recurring_revenue', 'closing_mrr')
        COMMENT = 'Monthly recurring revenue at the end of the selected period.',
    SUBSCRIBER_DAILY_SNAPSHOT.OPENING_MRR
        NON ADDITIVE BY (SUBSCRIBER_DAILY_SNAPSHOT.SNAPSHOT_DATE DESC NULLS LAST)
        AS SUM(mrr_amount)
        COMMENT = 'Monthly recurring revenue at the beginning of the selected period.',
    -- Cohort retention. Unlike active_subscribers this is not a stock taken on one day: it counts every
    -- subscription active at any point in the group, which is what a months_since_conversion cohort needs
    -- (subscriptions in one cohort month reach each tenure month on different dates).
    SUBSCRIBER_DAILY_SNAPSHOT.RETAINED_SUBSCRIPTIONS
        AS COUNT(DISTINCT IFF(subscriber_status = 'Active', subscription_id, NULL))
        WITH SYNONYMS = ('cohort_active_subscriptions', 'surviving_subscriptions')
        COMMENT = 'Distinct subscriptions active at any point in the selected group. Group by subscriptions.cohort_month and months_since_conversion for cohort retention: month 0 is the cohort size, and each later month divided by month 0 is the share retained. Do not filter by date for this; for the subscriber count on a date use active_subscribers.',

    -- Subscription events
    SUBSCRIPTION_EVENTS.CHURNED_SUBSCRIPTIONS
        AS COUNT(DISTINCT IFF(subscription_action IN ('Expired', 'Renewal failed, will not retry', 'Canceled'), subscription_id, NULL))
        WITH SYNONYMS = ('churned_subscribers', 'cancellations', 'lost_subscriptions', 'churn_count')
        COMMENT = 'Distinct subscriptions with a churn event (Canceled, Expired, or Renewal failed, will not retry) in the period.',
    SUBSCRIPTION_EVENTS.RENEWALS
        AS COUNT(DISTINCT IFF(subscription_action = 'Renewed', subscription_action_id, NULL))
        WITH SYNONYMS = ('renewed_subscriptions', 'rebills')
        COMMENT = 'Successful renewal charges in the period.',
    SUBSCRIPTION_EVENTS.FAILED_RENEWALS
        AS COUNT(DISTINCT IFF(subscription_action IN ('Renewal failed, will retry', 'Renewal failed, will not retry'), subscription_action_id, NULL))
        WITH SYNONYMS = ('payment_failures')
        COMMENT = 'Failed renewal attempts in the period, whether or not Piano will retry.',
    SUBSCRIPTION_EVENTS.AUTO_RENEW_DISABLED_SUBSCRIPTIONS
        AS COUNT(DISTINCT IFF(subscription_action = 'Auto-renew disabled', subscription_id, NULL))
        WITH SYNONYMS = ('cancellation_requests', 'turned_off_auto_renew')
        COMMENT = 'Distinct subscriptions that turned off auto-renew in the period (they churn at the end of their paid period unless re-enabled).',
    SUBSCRIPTION_EVENTS.NEW_MRR AS SUM(IFF(subscription_action = 'New subscription', mrr_change_amount, 0))
        COMMENT = 'Monthly recurring revenue added by new subscriptions in the period.',
    SUBSCRIPTION_EVENTS.CHURNED_MRR AS -SUM(IFF(subscription_action IN ('Expired', 'Renewal failed, will not retry', 'Canceled'), mrr_change_amount, 0))
        WITH SYNONYMS = ('lost_mrr')
        COMMENT = 'Monthly recurring revenue lost to churn in the period, as a positive amount.',
    SUBSCRIPTION_EVENTS.OTHER_MRR_CHANGE AS SUM(IFF(subscription_action NOT IN ('New subscription', 'Expired', 'Renewal failed, will not retry', 'Canceled'), mrr_change_amount, 0))
        WITH SYNONYMS = ('expansion_mrr', 'contraction_mrr', 'upgrade_mrr')
        COMMENT = 'Change in monthly recurring revenue from everything other than new subscriptions and churn: upgrades and price changes at renewal. new_mrr minus churned_mrr plus other_mrr_change equals net_mrr_change.',
    SUBSCRIPTION_EVENTS.NET_MRR_CHANGE AS SUM(mrr_change_amount)
        WITH SYNONYMS = ('mrr_movement')
        COMMENT = 'Net change in monthly recurring revenue from all subscription events in the period: new, churned, price changes at renewal and upgrades. Equals closing MRR minus the MRR at the end of the previous period.',
    SUBSCRIPTION_EVENTS.BILLED_REVENUE AS SUM(subscription_events.charged_amount)
        WITH SYNONYMS = ('billings', 'subscription_revenue', 'total_value', 'gross_revenue')
        COMMENT = 'Revenue charged in the period from new subscriptions, renewals and upgrades, excluding tax. App store charges are an estimate of list price less store fee, and app store renewals use the last known charge. Refunds are not deducted.',
    SUBSCRIPTION_EVENTS.CHARGED_SUBSCRIPTIONS AS COUNT(DISTINCT IFF(subscription_events.charged_amount IS NOT NULL, subscription_id, NULL))
        COMMENT = 'Distinct subscriptions charged at least once in the period.',

    -- Piano retention benchmark. One row per month, so AVG returns the curve value at each benchmark_month.
    PIANO_RETENTION_BENCHMARK.BENCHMARK_RETENTION_MONTHLY_MEDIAN AS AVG(piano_retention_benchmark.monthly_p50)
        COMMENT = 'Piano benchmark: median share (0 to 1) of monthly-plan subscriptions still active, by benchmark_month.',
    PIANO_RETENTION_BENCHMARK.BENCHMARK_RETENTION_MONTHLY_P25 AS AVG(piano_retention_benchmark.monthly_p25)
        COMMENT = 'Piano benchmark: 25th percentile share (0 to 1) of monthly-plan subscriptions still active, by benchmark_month.',
    PIANO_RETENTION_BENCHMARK.BENCHMARK_RETENTION_MONTHLY_P75 AS AVG(piano_retention_benchmark.monthly_p75)
        COMMENT = 'Piano benchmark: 75th percentile share (0 to 1) of monthly-plan subscriptions still active, by benchmark_month.',
    PIANO_RETENTION_BENCHMARK.BENCHMARK_RETENTION_ANNUAL_MEDIAN AS AVG(piano_retention_benchmark.annual_p50)
        COMMENT = 'Piano benchmark: median share (0 to 1) of annual-plan subscriptions still active, by benchmark_month.',
    PIANO_RETENTION_BENCHMARK.BENCHMARK_RETENTION_ANNUAL_P25 AS AVG(piano_retention_benchmark.annual_p25)
        COMMENT = 'Piano benchmark: 25th percentile share (0 to 1) of annual-plan subscriptions still active, by benchmark_month.',
    PIANO_RETENTION_BENCHMARK.BENCHMARK_RETENTION_ANNUAL_P75 AS AVG(piano_retention_benchmark.annual_p75)
        COMMENT = 'Piano benchmark: 75th percentile share (0 to 1) of annual-plan subscriptions still active, by benchmark_month.',

    -- Derived
    AVERAGE_REVENUE_PER_SUBSCRIPTION AS subscription_events.billed_revenue / NULLIFZERO(subscription_events.charged_subscriptions)
        WITH SYNONYMS = ('earned_ltv', 'lifetime_value', 'ltv', 'revenue_per_subscription')
        COMMENT = 'Revenue charged per subscription charged. With no start date (all time up to a date) it is the average earned lifetime value to that date; with a period filter it is the average charged per subscription in that period.',
    EXPOSURE_RATE_LANDING_PAGE AS exposures.exposed_visitors_landing_page_us_canada / NULLIFZERO(daily_visitors.distinct_visitors)
        WITH SYNONYMS = ('landing_page_reach', 'landing_page_exposure_rate')
        COMMENT = 'Share of US and Canada visitors who saw a Subscription Landing Page: distinct US and Canada visitors exposed to one divided by distinct US and Canada visitors. Reliable for Web only.',
    EXPOSURE_RATE_RIBBON AS exposures.exposed_visitors_ribbon_us_canada / NULLIFZERO(daily_visitors.distinct_visitors)
        WITH SYNONYMS = ('ribbon_reach', 'ribbon_exposure_rate')
        COMMENT = 'Share of US and Canada visitors who saw a Ribbon: distinct US and Canada visitors exposed to one divided by distinct US and Canada visitors. Reliable for Web only.',
    AVERAGE_CONVERSION_VALUE AS conversion_touchpoints.conversion_revenue / NULLIFZERO(conversion_touchpoints.conversions)
        WITH SYNONYMS = ('average_order_value', 'aov')
        COMMENT = 'First-period revenue per sign-up, excluding tax.',
    ARPU AS subscriber_daily_snapshot.mrr / NULLIFZERO(subscriber_daily_snapshot.active_subscribers)
        WITH SYNONYMS = ('average_revenue_per_user', 'arpu_monthly', 'mrr_per_subscriber')
        COMMENT = 'Monthly recurring revenue per active subscription at the end of the period.',
    CHURN_RATE AS subscription_events.churned_subscriptions / NULLIFZERO(subscriber_daily_snapshot.opening_active_subscribers)
        WITH SYNONYMS = ('subscriber_churn_rate', 'cancellation_rate')
        COMMENT = 'Subscriptions churned during the selected period divided by active subscriptions at the beginning of that period.',
    CONVERSION_RATE AS ZEROIFNULL(conversion_touchpoints.conversions) / NULLIFZERO(exposures.exposed_visitors)
        COMMENT = 'Sign-ups divided by distinct visitors exposed to any Composer experience. Web only; see exposed_visitors.',
    CONVERSION_RATE_LANDING_PAGE AS conversion_touchpoints.conversions_landing_page / NULLIFZERO(exposures.exposed_visitors_landing_page)
        COMMENT = 'Landing page sign-ups divided by distinct visitors exposed to a Subscription Landing Page template.',
    CONVERSION_RATE_PAYWALL AS conversion_touchpoints.conversions_paywall / NULLIFZERO(exposures.exposed_visitors_paywall)
        COMMENT = 'Paywall sign-ups divided by distinct visitors exposed to a Paywall template.',
    CONVERSION_RATE_RIBBON AS conversion_touchpoints.conversions_ribbon / NULLIFZERO(exposures.exposed_visitors_ribbon)
        COMMENT = 'Ribbon sign-ups divided by distinct visitors exposed to a Ribbon template.',
    EXPOSURE_RATE_PAYWALL AS exposures.exposed_visitors_paywall_us_canada / NULLIFZERO(daily_visitors.distinct_visitors)
        WITH SYNONYMS = ('paywall_reach', 'paywall_exposure_rate')
        COMMENT = 'Share of US and Canada visitors who saw a paywall: distinct US and Canada visitors exposed to a Paywall template divided by distinct US and Canada visitors. Reliable for Web only.',
    MRR_GROWTH_RATE AS (subscriber_daily_snapshot.mrr - subscriber_daily_snapshot.opening_mrr) / NULLIFZERO(subscriber_daily_snapshot.opening_mrr)
        COMMENT = 'Change in monthly recurring revenue from the start to the end of the period, as a share of opening MRR.',
    NET_SUBSCRIBER_CHANGE AS subscriber_daily_snapshot.active_subscribers - subscriber_daily_snapshot.opening_active_subscribers
        WITH SYNONYMS = ('net_adds', 'subscriber_growth')
        COMMENT = 'Active subscriptions at the end of the period minus active subscriptions at the start.'
)

COMMENT = 'BBC.com subscriptions and audience: CTA exposures, sign-ups split into paid and organic, subscriber stock, MRR, churn and renewals, US/Canada visitors and worldwide web page views. Built by dbt (model sv_bbc_com).'

AI_SQL_GENERATION 'Filter and group by dates, geographies, device_platforms, experiences, templates, terms, offers and subscriptions columns rather than fact columns; every fact joins to those tables. For a period such as "last month", filter dates.year_month or dates.date_day; today is partial, so use dates up to yesterday. Subscriber metrics (active_subscribers, mrr, opening_*) are stock measures: never sum them across days; the metric already takes the first or last day of the period. For cohort retention use retained_subscriptions grouped by subscriptions.cohort_month and months_since_conversion, without a date filter, and divide each month by month 0; compare with the piano_retention_benchmark metrics by benchmark_month, which are shares from 0 to 1. Device platform on subscription facts is the platform of the original conversion. Web and Mobile App experiences and templates are separate: an experience runs on one app type only (experiences.is_app_experience), so filter rate denominators to the same app type. On the mobile app, exposure visitor_id is not a stable visitor identifier (iOS gives a new one per exposure), so do not compute app exposure rates or app conversion rates per exposed visitor; report app exposures with exposure_events and explain why. distinct_visitors covers web and app in the United States and Canada only; page view metrics cover web only, worldwide. Ad revenue is not available. For subscription metrics (subscriber_daily_snapshot, subscription_events, conversion_touchpoints) filter or group by market with subscriptions.subscription_country, not geographies: geo tracking is often Unknown, whereas every subscription is sold in the United states or Canada. Use geographies for visitor, exposure and page view metrics. Country names are sentence case, for example ''United states'' and ''United kingdom''.'

AI_VERIFIED_QUERIES (
    subscribers_and_mrr_by_month AS (
        QUESTION 'How many active subscribers and how much MRR did we have at the end of each month this year?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS dates.year_month METRICS subscriber_daily_snapshot.active_subscribers, subscriber_daily_snapshot.mrr, arpu WHERE dates.is_current_year AND NOT dates.is_today) ORDER BY year_month'
    ),
    churn_rate_by_month AS (
        QUESTION 'What was the monthly churn rate over the last six months?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS dates.year_month METRICS subscription_events.churned_subscriptions, subscriber_daily_snapshot.opening_active_subscribers, churn_rate WHERE dates.date_day >= DATEADD(MONTH, -6, DATE_TRUNC(MONTH, CURRENT_DATE)) AND dates.date_day < DATE_TRUNC(MONTH, CURRENT_DATE)) ORDER BY year_month'
    ),
    paid_vs_organic_signups_last_month AS (
        QUESTION 'How many sign-ups came from paid media versus organic last month?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} METRICS conversion_touchpoints.conversions, conversion_touchpoints.paid_conversions, conversion_touchpoints.organic_conversions WHERE dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM''))'
    ),
    monthly_plan_cohort_retention AS (
        QUESTION 'How many monthly-plan subscriptions from each sign-up month were still active in each month after sign-up?'
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS subscriptions.cohort_month, subscriber_daily_snapshot.months_since_conversion METRICS subscriber_daily_snapshot.retained_subscriptions WHERE terms.billing_period = ''1 month'' AND subscriptions.cohort_month >= TO_CHAR(DATEADD(MONTH, -12, CURRENT_DATE), ''YYYY-MM'')) ORDER BY cohort_month, months_since_conversion'
    ),
    signups_by_billing_channel AS (
        QUESTION 'How many sign-ups came through web checkout versus the app stores last month?'
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS terms.billing_channel METRICS conversion_touchpoints.conversions, conversion_touchpoints.conversion_revenue WHERE dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY conversions DESC'
    ),
    web_paywall_exposure_rate AS (
        QUESTION 'What share of web visitors saw the paywall each week?'
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS dates.week_start_date METRICS exposures.exposed_visitors_paywall, daily_visitors.distinct_visitors, exposure_rate_paywall WHERE device_platforms.app_type = ''Web'' AND NOT dates.is_today AND dates.date_day >= DATEADD(WEEK, -8, CURRENT_DATE)) ORDER BY week_start_date'
    ),
    pageviews_by_pillar_yesterday AS (
        QUESTION 'Which content pillars got the most page views yesterday?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS page_views.content_pillar METRICS page_views.pageviews, page_views.page_view_visitors, page_views.time_spent_per_visitor_seconds WHERE dates.is_yesterday) ORDER BY pageviews DESC'
    )
)
