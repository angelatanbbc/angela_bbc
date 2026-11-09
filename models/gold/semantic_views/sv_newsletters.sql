{{
    config(
        materialized='semantic_view',
        copy_grants=true,
        static_analysis='off',
        tags=['semantic_view', 'newsletter']
    )
}}

{#-
    Newsletter acquisition semantic view for Cortex Analyst and SEMANTIC_VIEW() queries, over the
    newsletter facts and their dimensions. Counts follow the newsletter acquisition dashboard
    (agg_newsletter_activity): page views are visits to the newsletters page, sign-ups the latest
    sign-up per visitor and newsletter. The body is passed straight to CREATE OR REPLACE SEMANTIC VIEW,
    so it follows Snowflake's semantic view syntax rather than the SQL style guide.

    Naming rule: every dimension, fact and metric name is unique across the view; the visit and sign-up
    facts prefix the attributes they share. Both facts join dates on the day of the visit or sign-up.
    Country comes from the facts, because dim_geography only has the regions of the US and Canada.
-#}

TABLES (
    -- Dimensions
    DATES AS {{ ref('dim_date') }}
        PRIMARY KEY (DATE_KEY)
        WITH SYNONYMS = ('calendar', 'days')
        COMMENT = 'Calendar dimension. One row per date. Visits join on the day of their latest display of the newsletters page, sign-ups on the day of the sign-up.',
    DEVICE_PLATFORMS AS {{ ref('dim_device_platform') }}
        PRIMARY KEY (DEVICE_PLATFORM_ID)
        WITH SYNONYMS = ('operating_system_groups', 'operating_systems', 'os', 'devices')
        COMMENT = 'Device platform: app type x device type x operating system group.',
    NEWSLETTERS AS {{ ref('dim_newsletter') }}
        PRIMARY KEY (NEWSLETTER_SK)
        WITH SYNONYMS = ('newsletter_titles', 'lists')
        COMMENT = 'Newsletters that can be signed up to on the newsletters page. One row per newsletter, matched on the lower-cased title.',

    -- Facts
    NEWSLETTER_VISITS AS {{ ref('fct_newsletter_page_visits') }}
        PRIMARY KEY (VISIT_ID)
        WITH SYNONYMS = ('newsletter_page_views', 'newsletter_page_visits', 'page_visits')
        COMMENT = 'Visits to BBC.com''s newsletters page. One row per visit with at least one display of the page, the "page view" the newsletter acquisition dashboard counts. Source and placement come from the visit''s latest display.',
    NEWSLETTER_SIGNUPS AS {{ ref('fct_newsletter_signups') }}
        PRIMARY KEY (NEWSLETTER_SIGNUP_SK)
        WITH SYNONYMS = ('signups', 'subscriptions_to_newsletters')
        COMMENT = 'Newsletter sign-ups on the newsletters page. One row per sign-up event and newsletter; one event can sign up to several newsletters. Repeat sign-ups are kept and flagged.'
)

RELATIONSHIPS (
    NEWSLETTER_VISITS_TO_DATES AS NEWSLETTER_VISITS (EVENT_DATE) REFERENCES DATES (DATE_KEY),
    NEWSLETTER_VISITS_TO_DEVICE_PLATFORMS AS NEWSLETTER_VISITS (DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    NEWSLETTER_SIGNUPS_TO_DATES AS NEWSLETTER_SIGNUPS (EVENT_DATE) REFERENCES DATES (DATE_KEY),
    NEWSLETTER_SIGNUPS_TO_DEVICE_PLATFORMS AS NEWSLETTER_SIGNUPS (DEVICE_PLATFORM_ID) REFERENCES DEVICE_PLATFORMS (DEVICE_PLATFORM_ID),
    NEWSLETTER_SIGNUPS_TO_NEWSLETTERS AS NEWSLETTER_SIGNUPS (NEWSLETTER_SK) REFERENCES NEWSLETTERS (NEWSLETTER_SK)
)

DIMENSIONS (
    -- Dates
    DATES.DATE_DAY AS date_day
        WITH SYNONYMS = ('date', 'day')
        COMMENT = 'Calendar date.',
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

    -- Newsletters
    NEWSLETTERS.NEWSLETTER_TITLE AS newsletter_title
        WITH SYNONYMS = ('newsletter', 'newsletter_name', 'list_name')
        COMMENT = 'Name of the newsletter, in its most common spelling.',

    -- Newsletter page visits
    NEWSLETTER_VISITS.VISIT_SOURCE AS src
        WITH SYNONYMS = ('traffic_source', 'source')
        COMMENT = 'Piano traffic source of the visit, in lower case, such as direct traffic, onsite, emails, advertisement, search engines or social media.',
    NEWSLETTER_VISITS.VISIT_SOURCE_DETAIL AS src_detail
        COMMENT = 'Detail of the traffic source: the referrer, search engine or social network.',
    NEWSLETTER_VISITS.VISIT_CAMPAIGN AS src_campaign
        COMMENT = 'Campaign tag on the visit.',
    NEWSLETTER_VISITS.VISIT_MEDIUM AS src_medium
        COMMENT = 'Medium tag on the visit.',
    NEWSLETTER_VISITS.VISIT_TEAM AS src_bbc_team
        WITH SYNONYMS = ('agency', 'bbc_team')
        COMMENT = 'Team tag on the link the visit came from, in lower case, such as studios, crm, editorial, or the paid media agencies 8ms and dbs; empty when untagged.',
    NEWSLETTER_VISITS.VISIT_PARTNER AS src_ptr_name
        COMMENT = 'Partner tag on the link the visit came from, such as bbc.com, salesforce or facebook.',
    NEWSLETTER_VISITS.VISIT_PLACEMENT AS at_link_origin
        WITH SYNONYMS = ('placement', 'link_origin', 'entry_point')
        COMMENT = 'Where the link to the newsletters page was, from its at_link_origin tag, such as homepage, featuresarticle, article or house; empty when the link had no tag.',
    NEWSLETTER_VISITS.VISIT_FORMAT AS at_format
        COMMENT = 'Format tag of the link to the newsletters page.',
    NEWSLETTER_VISITS.VISIT_BROWSER_GROUP AS browser_group
        WITH SYNONYMS = ('browser')
        COMMENT = 'Browser group of the visit.',
    NEWSLETTER_VISITS.VISIT_COUNTRY AS geo_country
        WITH SYNONYMS = ('country', 'market')
        COMMENT = 'Country of the visit, in sentence case, such as United states.',
    NEWSLETTER_VISITS.VISIT_ACCOUNT_STATUS AS account_status
        WITH SYNONYMS = ('signed_in_status', 'login_status')
        COMMENT = 'The visitor''s status before the visit''s first sign-up: Signed in, Account, not signed in, or Not identified (unknown, not "no account").',
    NEWSLETTER_VISITS.VISIT_SIGNED_UP AS signed_up
        COMMENT = 'Whether the visit included a newsletter sign-up.',
    NEWSLETTER_VISITS.VISIT_IS_SUSPECTED_AUTOMATED AS is_suspected_automated
        WITH SYNONYMS = ('bot_traffic', 'automated_traffic')
        COMMENT = 'Whether the visit displayed the newsletters page more than 20 times: suspected automated traffic, nearly all from France in April to June 2026, with almost no sign-ups.',

    -- Newsletter sign-ups
    NEWSLETTER_SIGNUPS.SIGNUP_SOURCE AS src
        COMMENT = 'Piano traffic source of the sign-up''s visit.',
    NEWSLETTER_SIGNUPS.SIGNUP_CAMPAIGN AS src_campaign
        COMMENT = 'Campaign tag on the sign-up''s visit.',
    NEWSLETTER_SIGNUPS.SIGNUP_TEAM AS src_bbc_team
        COMMENT = 'Team tag on the link the sign-up''s visit came from, in lower case, such as studios, crm, editorial, 8ms or dbs.',
    NEWSLETTER_SIGNUPS.SIGNUP_PLACEMENT AS at_link_origin
        COMMENT = 'Where the link to the newsletters page was for the sign-up''s visit (at_link_origin tag).',
    NEWSLETTER_SIGNUPS.SIGNUP_COUNTRY AS geo_country
        COMMENT = 'Country of the sign-up, in sentence case.',
    NEWSLETTER_SIGNUPS.SIGNUP_ACCOUNT_STATUS AS account_status
        COMMENT = 'The visitor''s status before the visit''s first sign-up: Signed in, Account, not signed in, or Not identified.',
    NEWSLETTER_SIGNUPS.SIGNUP_IS_SUSPECTED_AUTOMATED AS is_suspected_automated
        COMMENT = 'Whether the sign-up''s visit is suspected automated traffic.',
    NEWSLETTER_SIGNUPS.IS_LATEST_FOR_VISITOR_TITLE AS is_latest_for_visitor_title
        COMMENT = 'Whether this is the visitor''s latest sign-up to the newsletter; the signups metric counts only these.'
)

METRICS (
    -- Newsletter page visits (day of the visit)
    NEWSLETTER_VISITS.PAGE_VISITS AS COUNT(visit_id)
        WITH SYNONYMS = ('page_views', 'newsletter_page_views', 'visits')
        COMMENT = 'Visits to the newsletters page, the dashboard''s page views.',
    NEWSLETTER_VISITS.PAGE_VISITORS AS COUNT(DISTINCT visitor_id)
        WITH SYNONYMS = ('unique_visitors')
        COMMENT = 'Distinct visitors (cookies) to the newsletters page.',
    NEWSLETTER_VISITS.VISITS_WITH_SIGNUP AS COUNT_IF(signed_up)
        WITH SYNONYMS = ('converting_visits')
        COMMENT = 'Visits to the newsletters page that included a sign-up.',

    -- Newsletter sign-ups (day of the sign-up)
    NEWSLETTER_SIGNUPS.SIGNUPS AS COUNT_IF(is_latest_for_visitor_title)
        WITH SYNONYMS = ('newsletter_signups', 'sign_ups', 'subscriptions')
        COMMENT = 'Newsletter sign-ups as the dashboard counts them: each visitor''s latest sign-up to each newsletter. A person signing up to three newsletters counts three.',
    NEWSLETTER_SIGNUPS.SIGNUP_VISITORS AS COUNT(DISTINCT IFF(is_latest_for_visitor_title, visitor_id, NULL))
        WITH SYNONYMS = ('distinct_signups', 'people_signed_up', 'unique_signups')
        COMMENT = 'Distinct visitors (cookies) who signed up, the dashboard''s distinct sign-ups.',
    NEWSLETTER_SIGNUPS.ALL_SIGNUP_ROWS AS COUNT(newsletter_signup_sk)
        COMMENT = 'Every sign-up to a newsletter, including repeat sign-ups by the same visitor.',

    -- Ratios, from the metrics above, so they stay right at any level of grouping
    VISIT_SIGNUP_RATE AS newsletter_visits.visits_with_signup / NULLIFZERO(newsletter_visits.page_visits)
        WITH SYNONYMS = ('conversion_rate', 'signup_rate')
        COMMENT = 'Share of visits to the newsletters page that included a sign-up.',
    NEWSLETTERS_PER_SIGNUP_VISITOR AS newsletter_signups.signups / NULLIFZERO(newsletter_signups.signup_visitors)
        COMMENT = 'Average number of newsletters each signing-up visitor signed up to.'
)

COMMENT = 'Newsletter acquisition on BBC.com''s newsletters page: visits to the page, sign-ups by newsletter, and where the visits came from (source, placement, campaign, agency, device and country), from 1 January 2026. Matches the newsletter acquisition dashboard. Built by dbt (model sv_newsletters).'

AI_SQL_GENERATION 'Counts follow the newsletter acquisition dashboard: page_visits (the dashboard''s page views) counts visits to the newsletters page, signups counts each visitor''s latest sign-up to each newsletter, and signup_visitors counts the people (cookies) who signed up. One sign-up event can include several newsletters, so signups is larger than signup_visitors; use signup_visitors for the number of people. Use newsletter_visits dimensions with visit metrics and newsletter_signups dimensions with sign-up metrics; the two facts only share dates and device platforms. Totals include visits flagged as suspected automated traffic, as the dashboard''s do; for conversion rates or real readers, filter them out with NOT newsletter_visits.visit_is_suspected_automated or NOT newsletter_signups.signup_is_suspected_automated. Only sign-ups on the newsletters page are here, not other sign-up points such as Meta lead forms. History starts on 1 January 2026. Traffic source and team values are lower case; the paid media agencies are the teams 8ms and dbs. Country names are sentence case, for example ''United states''. For a period such as "last month", filter dates.year_month or dates.date_day; data runs to yesterday.'

AI_VERIFIED_QUERIES (
    signups_by_newsletter_last_month AS (
        QUESTION 'Which newsletters got the most sign-ups last month?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS newsletters.newsletter_title METRICS newsletter_signups.signups, newsletter_signups.signup_visitors WHERE dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY signups DESC'
    ),
    visits_and_signup_rate_by_week AS (
        QUESTION 'How many visits did the newsletters page get each week over the last eight weeks, and what share signed up, excluding suspected automated traffic?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS dates.week_start_date METRICS newsletter_visits.page_visits, newsletter_visits.visits_with_signup, visit_signup_rate WHERE NOT newsletter_visits.visit_is_suspected_automated AND dates.date_day >= DATEADD(WEEK, -8, DATE_TRUNC(WEEK, CURRENT_DATE))) ORDER BY week_start_date'
    ),
    signups_by_placement_last_month AS (
        QUESTION 'Where on the site did newsletter sign-ups come from last month?'
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS newsletter_signups.signup_placement METRICS newsletter_signups.signups WHERE dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY signups DESC'
    )
)
