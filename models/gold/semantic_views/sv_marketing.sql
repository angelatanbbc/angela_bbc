{{
    config(
        materialized='semantic_view',
        copy_grants=true,
        static_analysis='off',
        tags=['semantic_view', 'marketing']
    )
}}

{#-
    Paid marketing semantic view for Cortex Analyst and SEMANTIC_VIEW() queries, over the Marketing
    Measurement Dashboard's gold tables, so its numbers match the dashboard. The body is passed straight
    to CREATE OR REPLACE SEMANTIC VIEW, so it follows Snowflake's semantic view syntax rather than the
    SQL style guide.

    Naming rule: every dimension, fact and metric name is unique across the view. campaign_days, the
    campaign economics table, keeps the plain names; the page view and visitor tables prefix the
    attributes they share with it. Each table joins dates on its own day.
-#}

TABLES (
    -- Dimensions
    DATES AS {{ ref('dim_date') }}
        PRIMARY KEY (DATE_KEY)
        WITH SYNONYMS = ('calendar', 'days')
        COMMENT = 'Calendar dimension. One row per date. Every table joins here on its own day: campaign_days and paid_page_views on the day of the spend or page view, visitor_funnel on the visitor''s first day in the stage (first paid day for All stages).',

    -- Facts
    CAMPAIGN_DAYS AS {{ ref('agg_marketing_campaign_daily') }}
        WITH SYNONYMS = ('campaigns', 'campaign_performance', 'campaign_economics', 'paid_media')
        COMMENT = 'Campaign economics by day: spend and delivery, paid page views, what the visitors who arrived went on to do, and the subscriptions the click-based attribution credits to paid media. One row per platform, campaign, funnel stage, agency and day. Every measure is additive, so every ratio is a sum divided by a sum.',
    PAID_PAGE_VIEWS AS {{ ref('agg_marketing_paid_page_views') }}
        WITH SYNONYMS = ('paid_traffic', 'paid_pageviews')
        COMMENT = 'Paid page views with the spend that bought them. One row per paid page view, plus one row per spend day with no page views. The day''s spend is split equally across its page views (Meta by ad and day, Google and Microsoft by campaign and day).',
    VISITOR_FUNNEL AS {{ ref('agg_marketing_stage_funnel') }}
        PRIMARY KEY (FUNNEL_STAGE, VISITOR_ID)
        WITH SYNONYMS = ('paid_visitor_funnel', 'funnel', 'paid_visitors', 'paywall_funnel')
        COMMENT = 'The paid visitor funnel as the dashboard''s Funnel tab counts it: what paid visitors went on to do (paywall seen and clicked, offer seen and clicked, subscription bought via the paywall or any route, newsletter sign-up), over time and in the same visit, with their LTS and RevOps bands. One row per paid visitor and funnel stage (TOF, MOF, BOF, BOF (Docs)), dated on their first day in that stage, plus one row per visitor for All stages, dated on their first paid day.'
)

RELATIONSHIPS (
    CAMPAIGN_DAYS_TO_DATES AS CAMPAIGN_DAYS (DATE_DAY) REFERENCES DATES (DATE_KEY),
    PAID_PAGE_VIEWS_TO_DATES AS PAID_PAGE_VIEWS (DATE_DAY) REFERENCES DATES (DATE_KEY),
    VISITOR_FUNNEL_TO_DATES AS VISITOR_FUNNEL (DATE_DAY) REFERENCES DATES (DATE_KEY)
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

    -- Campaign days
    CAMPAIGN_DAYS.PLATFORM AS platform
        WITH SYNONYMS = ('ad_network', 'channel')
        COMMENT = 'Ad platform the campaign''s spend is on: meta, google or microsoft (meta for campaigns with no spend).',
    CAMPAIGN_DAYS.CAMPAIGN AS src_campaign
        WITH SYNONYMS = ('campaign_name')
        COMMENT = 'Campaign name as Piano records it on the visit (src_campaign).',
    CAMPAIGN_DAYS.FUNNEL_STAGE AS funnel_stage
        WITH SYNONYMS = ('stage')
        COMMENT = 'Funnel stage of the campaign: TOF (top), MOF (middle) or BOF (bottom of funnel); empty when the campaign name has no stage.',
    CAMPAIGN_DAYS.FUNNEL_STAGE_V2 AS funnel_stage_v2
        COMMENT = 'Funnel stage with BOF campaigns that have Docs in their name split out: TOF, MOF, BOF or BOF (Docs).',
    CAMPAIGN_DAYS.AGENCY AS src_bbc_team
        WITH SYNONYMS = ('media_agency', 'paid_media_agency', 'bbc_team')
        COMMENT = 'Paid media agency, in lower case: 8ms or dbs.',

    -- Paid page views
    PAID_PAGE_VIEWS.AD_PLATFORM AS platform
        COMMENT = 'Ad platform of the page view''s spend: meta, google or microsoft.',
    PAID_PAGE_VIEWS.AD_NAME AS ad_name
        WITH SYNONYMS = ('creative', 'ad')
        COMMENT = 'Name of the ad as its platform reports it; for Google and Microsoft, the campaign name from the agencies'' sheet.',
    PAID_PAGE_VIEWS.AD_SET_NAME AS adset_name
        WITH SYNONYMS = ('ad_set', 'adset')
        COMMENT = 'Meta ad set name.',
    PAID_PAGE_VIEWS.AD_CAMPAIGN_NAME AS campaign_name
        WITH SYNONYMS = ('platform_campaign')
        COMMENT = 'Campaign name as the ad platform reports it.',
    PAID_PAGE_VIEWS.PAGE_VIEW_CAMPAIGN AS src_campaign
        COMMENT = 'Campaign name as Piano records it on the page view''s visit.',
    PAID_PAGE_VIEWS.PAGE_VIEW_FUNNEL_STAGE AS funnel_stage
        COMMENT = 'Funnel stage of the page view''s campaign: TOF, MOF or BOF.',
    PAID_PAGE_VIEWS.PAGE_VIEW_AGENCY AS src_bbc_team
        COMMENT = 'Paid media agency of the page view''s visit, in lower case: 8ms or dbs.',
    PAID_PAGE_VIEWS.SPEND_CURRENCY AS currency
        COMMENT = 'Currency of the ad account: USD or GBP for Meta; empty for Google and Microsoft spend from the agencies'' sheet.',
    PAID_PAGE_VIEWS.HAS_PAGE_VIEW AS has_page_view
        COMMENT = 'FALSE on rows that only carry spend for a day with no paid page views.',
    PAID_PAGE_VIEWS.CONTENT_PILLAR AS content_pillar
        WITH SYNONYMS = ('pillar')
        COMMENT = 'Content pillar of the page, such as News, Culture or Travel.',
    PAID_PAGE_VIEWS.CONTENT_SECTION AS content_section
        WITH SYNONYMS = ('section')
        COMMENT = 'Content section of the page.',
    PAID_PAGE_VIEWS.CONTENT_TYPE AS content_type
        COMMENT = 'Content type of the page, such as article, indexPage, docs-series or docs-episode.',
    PAID_PAGE_VIEWS.PAGE_TITLE AS page_title
        WITH SYNONYMS = ('article', 'page')
        COMMENT = 'Title of the page.',
    PAID_PAGE_VIEWS.DEVICE_TYPE AS device_type
        WITH SYNONYMS = ('device')
        COMMENT = 'Device type: Mobile Phone, Desktop, Tablet, Other or Unknown.',
    PAID_PAGE_VIEWS.OS_GROUP AS os_group
        WITH SYNONYMS = ('operating_system', 'os')
        COMMENT = 'Operating system group, such as iOS or Android.',
    PAID_PAGE_VIEWS.BROWSER_GROUP AS browser_group
        WITH SYNONYMS = ('browser')
        COMMENT = 'Browser group, such as Chrome, Safari, Edge or Firefox.',
    PAID_PAGE_VIEWS.GEO_COUNTRY AS geo_country
        WITH SYNONYMS = ('country', 'market')
        COMMENT = 'Country of the page view, in sentence case, such as United states.',
    PAID_PAGE_VIEWS.GEO_REGION AS geo_region
        WITH SYNONYMS = ('region', 'state')
        COMMENT = 'Region or state of the page view.',
    PAID_PAGE_VIEWS.VISITOR_NEW_RETURN AS visitor_new_return
        WITH SYNONYMS = ('new_or_returning')
        COMMENT = 'New or Returning visitor, as Piano records it.',
    PAID_PAGE_VIEWS.IS_VISIT_BOUNCE AS visit_bounce
        COMMENT = 'Whether the page view''s visit was a one-page bounce.',
    PAID_PAGE_VIEWS.PAGE_VIEW_REVOPS_BAND AS ro_band
        COMMENT = 'RevOps score band of the page view: RevOps 80+, RevOps 50-79, RevOps <50 or No score.',
    PAID_PAGE_VIEWS.PAGE_VIEW_LTS_BAND AS lts_band
        COMMENT = 'LTS (likelihood to subscribe) band of the page view: LTS 90+, LTS 70-89, LTS 40-69, LTS 20-39, LTS 0-19 or No score.',

    -- Visitor funnel (one row per visitor and stage, plus All stages)
    VISITOR_FUNNEL.VISITOR_FUNNEL_STAGE AS funnel_stage
        WITH SYNONYMS = ('stage', 'funnel_stage', 'all_stages')
        COMMENT = 'TOF, MOF, BOF, BOF (Docs) (BOF campaigns with Docs in their name), or All stages, where each visitor appears once across the four stages. Totals across stages come from All stages; never add the stage rows together.',
    VISITOR_FUNNEL.VISITOR_AGENCY AS src_bbc_team
        COMMENT = 'Paid media agency of the visitor''s first campaign in the stage, in lower case: 8ms or dbs.',
    VISITOR_FUNNEL.LANDING_CONTENT_PILLAR AS landing_content_pillar
        WITH SYNONYMS = ('landing_pillar')
        COMMENT = 'Content pillar of the first page the visitor landed on in the stage.',
    VISITOR_FUNNEL.LTS_BAND_ON_ARRIVAL AS lts_band_on_arrival
        WITH SYNONYMS = ('lts_band', 'likelihood_to_subscribe_band', 'lts_tier', 'score_band')
        COMMENT = 'LTS (likelihood to subscribe) band on the visitor''s first scored paid page view, before the visit can move it: LTS 90+, LTS 70-89, LTS 40-69, LTS 20-39, LTS 0-19 or No score. The dashboard''s default band and the fair one for targeting questions.',
    VISITOR_FUNNEL.REVOPS_BAND_ON_ARRIVAL AS revops_band_on_arrival
        WITH SYNONYMS = ('revops_band', 'revops_tier')
        COMMENT = 'RevOps band on the visitor''s first scored paid page view: RevOps 90+, RevOps 80-89, RevOps 50-79, RevOps under 50 or No score.',
    VISITOR_FUNNEL.LTS_BAND_BEST AS lts_band_best
        COMMENT = 'LTS band of the visitor''s highest LTS score over their paid page views. Scores rise during a visit that ends in a purchase, so this flatters converters; prefer lts_band_on_arrival.',
    VISITOR_FUNNEL.REVOPS_BAND_BEST AS revops_band_best
        COMMENT = 'RevOps band of the visitor''s highest RevOps score over their paid page views: RevOps 90+, RevOps 80-89, RevOps 50-79, RevOps under 50 or No score.'
)

METRICS (
    -- Campaign days: delivery and spend (day of the spend)
    CAMPAIGN_DAYS.SPEND AS SUM(spend)
        WITH SYNONYMS = ('cost', 'ad_spend', 'media_spend', 'amount_spent')
        COMMENT = 'Paid media spend, in each ad account''s currency (almost all USD; see the view guidance).',
    CAMPAIGN_DAYS.IMPRESSIONS AS SUM(impressions)
        COMMENT = 'Ad impressions (Meta only; 0 for Google and Microsoft).',
    CAMPAIGN_DAYS.LINK_CLICKS AS SUM(clicks)
        WITH SYNONYMS = ('clicks')
        COMMENT = 'Ad link clicks (Meta only; 0 for Google and Microsoft).',

    -- Campaign days: paid traffic (day of the page view)
    CAMPAIGN_DAYS.PAID_PAGE_VIEWS AS SUM(page_views)
        WITH SYNONYMS = ('page_views', 'paid_pageviews')
        COMMENT = 'Page views of paid visits.',
    CAMPAIGN_DAYS.PAID_VISITS AS SUM(visits)
        WITH SYNONYMS = ('visits', 'sessions')
        COMMENT = 'Paid visits (a visit is counted on each day it has page views).',
    CAMPAIGN_DAYS.PURCHASES_ON_PAID_PAGE_VIEW AS SUM(purchases_on_page_view)
        COMMENT = 'Subscription purchases made on a paid page view (in the paid visit itself).',

    -- Campaign days: visitor outcomes (day the visitor first arrived from the campaign)
    CAMPAIGN_DAYS.ARRIVALS AS SUM(arrivals)
        WITH SYNONYMS = ('paid_arrivals', 'visitors', 'paid_visitors_arrived')
        COMMENT = 'Visitors arriving from a campaign for the first time. A visitor who arrives from two campaigns counts once for each.',
    CAMPAIGN_DAYS.ARRIVALS_SAW_PAYWALL AS SUM(saw_paywall)
        COMMENT = 'Arrivals who saw a paywall afterwards.',
    CAMPAIGN_DAYS.ARRIVALS_CLICKED_PAYWALL AS SUM(interacted)
        COMMENT = 'Arrivals who clicked a paywall afterwards.',
    CAMPAIGN_DAYS.ARRIVALS_SAW_OFFER AS SUM(saw_offer)
        COMMENT = 'Arrivals who saw a subscription offer afterwards.',
    CAMPAIGN_DAYS.ARRIVALS_CLICKED_OFFER AS SUM(interacted_offer)
        COMMENT = 'Arrivals who clicked a subscription offer afterwards.',
    CAMPAIGN_DAYS.ARRIVALS_CONVERTED AS SUM(converted)
        WITH SYNONYMS = ('converters', 'converted_visitors')
        COMMENT = 'Arrivals who bought a subscription afterwards, by any route (over time, not windowed).',
    CAMPAIGN_DAYS.ARRIVALS_CONVERTED_SAME_VISIT AS SUM(converted_same_visit)
        COMMENT = 'Arrivals who bought a subscription in the same visit.',
    CAMPAIGN_DAYS.ARRIVALS_SIGNED_UP_NEWSLETTER AS SUM(newsletter_signups)
        COMMENT = 'Arrivals who signed up to a newsletter afterwards.',
    CAMPAIGN_DAYS.CONVERTERS_LAST_PAID_TOUCH AS SUM(converted_last_touch)
        COMMENT = 'Converting visitors for whom this campaign was the last paid touch.',

    -- Campaign days: attributed credit (day of the click)
    CAMPAIGN_DAYS.PAID_ATTRIBUTED_SUBSCRIPTIONS AS SUM(paid_attributed_subscriptions)
        WITH SYNONYMS = ('paid_subs', 'paid_subscriptions', 'attributed_subscriptions', 'mta_subscriptions')
        COMMENT = 'Subscriptions credited to the campaign''s clicks by the click-based attribution, position-based model.',
    CAMPAIGN_DAYS.PAID_LAST_TOUCH_SUBSCRIPTIONS AS SUM(paid_last_touch_subscriptions)
        COMMENT = 'Subscriptions whose last touch before the purchase was a click on the campaign.',

    -- Paid page views (day of the page view)
    PAID_PAGE_VIEWS.PAGE_VIEW_COUNT AS COUNT(pageview_id)
        COMMENT = 'Paid page views. Same total as paid_page_views; use it when slicing by content, device, geography, ad or score band.',
    PAID_PAGE_VIEWS.PAGE_VIEW_VISITS AS COUNT(DISTINCT visit_id)
        COMMENT = 'Paid visits with a page view in the selection.',
    PAID_PAGE_VIEWS.PAGE_VIEW_VISITORS AS COUNT(DISTINCT visitor_id)
        COMMENT = 'Distinct visitors (cookies) with a paid page view in the selection.',
    PAID_PAGE_VIEWS.PAGE_VIEW_SPEND AS SUM(spend_per_page_view)
        COMMENT = 'Spend split equally across the day''s page views of each ad (Meta) or campaign (Google, Microsoft); spend-only days keep theirs. Adds up to spend.',
    PAID_PAGE_VIEWS.BOUNCE_RATE AS COUNT(DISTINCT IFF(visit_bounce, visit_id, NULL)) / NULLIFZERO(COUNT(DISTINCT visit_id))
        COMMENT = 'Share of paid visits that were one-page bounces.',
    PAID_PAGE_VIEWS.AVERAGE_PAGE_DURATION_SECONDS AS AVG(page_duration_seconds)
        WITH SYNONYMS = ('time_on_page')
        COMMENT = 'Average seconds spent on a paid page view.',
    PAID_PAGE_VIEWS.PAGE_VIEW_SUBSCRIPTION_SELECTS AS SUM(subscription_select_count)
        COMMENT = 'Subscription offers selected on paid page views.',
    PAID_PAGE_VIEWS.PAGE_VIEW_PURCHASES AS SUM(vx_conversion_count)
        COMMENT = 'Subscription purchases made on paid page views.',
    PAID_PAGE_VIEWS.PAGE_VIEW_NEWSLETTER_SIGNUPS AS SUM(newsletter_subscribe_count)
        COMMENT = 'Newsletter sign-ups made on paid page views.',

    -- Visitor funnel (day of the visitor's first day in the stage); distinct visitors, so filter or group
    -- by visitor_funnel_stage and take totals from All stages
    VISITOR_FUNNEL.FUNNEL_VISITORS AS COUNT(DISTINCT visitor_id)
        WITH SYNONYMS = ('visitors', 'paid_visitors', 'unique_visitors')
        COMMENT = 'Paid visitors whose first day in the stage falls in the period.',
    VISITOR_FUNNEL.VISITORS_SAW_PAYWALL AS COUNT(DISTINCT IFF(saw_paywall = 1, visitor_id, NULL))
        WITH SYNONYMS = ('paywall_seen', 'saw_the_paywall')
        COMMENT = 'Paid visitors who saw a paywall afterwards, in any later visit (overall).',
    VISITOR_FUNNEL.VISITORS_INTERACTED_PAYWALL AS COUNT(DISTINCT IFF(interacted = 1, visitor_id, NULL))
        WITH SYNONYMS = ('interacted_with_the_paywall', 'clicked_paywall', 'paywall_interactions')
        COMMENT = 'Paid visitors who clicked a paywall afterwards, in any later visit (overall).',
    VISITOR_FUNNEL.VISITORS_SAW_OFFER AS COUNT(DISTINCT IFF(saw_offer = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who saw a subscription offer afterwards, in any later visit (overall).',
    VISITOR_FUNNEL.VISITORS_INTERACTED_OFFER AS COUNT(DISTINCT IFF(interacted_offer = 1, visitor_id, NULL))
        WITH SYNONYMS = ('clicked_offer')
        COMMENT = 'Paid visitors who clicked a subscription offer afterwards, in any later visit (overall).',
    VISITOR_FUNNEL.VISITORS_CONVERTED_VIA_PAYWALL AS COUNT(DISTINCT IFF(converted_via_paywall = 1, visitor_id, NULL))
        WITH SYNONYMS = ('bought_via_the_paywall', 'paywall_conversions')
        COMMENT = 'Paid visitors who bought a subscription via the paywall afterwards, in any later visit (overall).',
    VISITOR_FUNNEL.VISITORS_CONVERTED AS COUNT(DISTINCT IFF(converted = 1, visitor_id, NULL))
        WITH SYNONYMS = ('converted_overall', 'converters', 'subscribers')
        COMMENT = 'Paid visitors who bought a subscription by any route afterwards, in any later visit (overall).',
    VISITOR_FUNNEL.VISITORS_SIGNED_UP_NEWSLETTER AS COUNT(DISTINCT IFF(newsletter_signup = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who signed up to a newsletter afterwards, in any later visit (overall).',
    VISITOR_FUNNEL.VISITORS_SAW_PAYWALL_SAME_VISIT AS COUNT(DISTINCT IFF(saw_paywall_same_visit = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who saw a paywall in the same visit as their arrival.',
    VISITOR_FUNNEL.VISITORS_INTERACTED_PAYWALL_SAME_VISIT AS COUNT(DISTINCT IFF(interacted_same_visit = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who clicked a paywall in the same visit as their arrival.',
    VISITOR_FUNNEL.VISITORS_SAW_OFFER_SAME_VISIT AS COUNT(DISTINCT IFF(saw_offer_same_visit = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who saw a subscription offer in the same visit as their arrival.',
    VISITOR_FUNNEL.VISITORS_INTERACTED_OFFER_SAME_VISIT AS COUNT(DISTINCT IFF(interacted_offer_same_visit = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who clicked a subscription offer in the same visit as their arrival.',
    VISITOR_FUNNEL.VISITORS_CONVERTED_VIA_PAYWALL_SAME_VISIT AS COUNT(DISTINCT IFF(converted_via_paywall_same_visit = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who bought a subscription via the paywall in the same visit as their arrival.',
    VISITOR_FUNNEL.VISITORS_CONVERTED_SAME_VISIT AS COUNT(DISTINCT IFF(converted_same_visit = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who bought a subscription by any route in the same visit as their arrival.',
    VISITOR_FUNNEL.VISITORS_SIGNED_UP_NEWSLETTER_SAME_VISIT AS COUNT(DISTINCT IFF(newsletter_signup_same_visit = 1, visitor_id, NULL))
        COMMENT = 'Paid visitors who signed up to a newsletter in the same visit as their arrival.',
    VISITOR_FUNNEL.AVERAGE_DAYS_TO_CONVERSION AS AVG(IFF(converted = 1, days_to_conversion, NULL))
        COMMENT = 'Average days from arriving in the stage to buying, for visitors who bought.',

    -- Ratios, from the metrics above, so they stay right at any level of grouping
    CTR AS campaign_days.link_clicks / NULLIFZERO(campaign_days.impressions)
        WITH SYNONYMS = ('click_through_rate')
        COMMENT = 'Link clicks per impression (Meta only).',
    CPM AS campaign_days.spend * 1000 / NULLIFZERO(campaign_days.impressions)
        COMMENT = 'Spend per thousand impressions (Meta only).',
    CPC AS campaign_days.spend / NULLIFZERO(campaign_days.link_clicks)
        WITH SYNONYMS = ('cost_per_click')
        COMMENT = 'Spend per link click (Meta only).',
    COST_PER_PAID_PAGE_VIEW AS campaign_days.spend / NULLIFZERO(campaign_days.paid_page_views)
        COMMENT = 'Spend per paid page view.',
    COST_PER_ARRIVAL AS campaign_days.spend / NULLIFZERO(campaign_days.arrivals)
        WITH SYNONYMS = ('cost_per_visitor')
        COMMENT = 'Spend per arrival.',
    ARRIVAL_CONVERSION_RATE AS campaign_days.arrivals_converted / NULLIFZERO(campaign_days.arrivals)
        COMMENT = 'Share of arrivals who bought a subscription afterwards.',
    ARRIVAL_PAYWALL_RATE AS campaign_days.arrivals_saw_paywall / NULLIFZERO(campaign_days.arrivals)
        COMMENT = 'Share of arrivals who saw a paywall afterwards.',
    COST_PER_CONVERTER AS campaign_days.spend / NULLIFZERO(campaign_days.arrivals_converted)
        COMMENT = 'Spend per arrival who bought a subscription afterwards.',
    CPA AS campaign_days.spend / NULLIFZERO(campaign_days.paid_attributed_subscriptions)
        WITH SYNONYMS = ('cost_per_acquisition', 'cost_per_subscription', 'mta_cpa')
        COMMENT = 'Spend per paid attributed subscription (position-based model), as on the Marketing Measurement Dashboard.',
    LAST_TOUCH_CPA AS campaign_days.spend / NULLIFZERO(campaign_days.paid_last_touch_subscriptions)
        COMMENT = 'Spend per subscription whose last touch was a paid click.',
    PAYWALL_SEEN_RATE AS visitor_funnel.visitors_saw_paywall / NULLIFZERO(visitor_funnel.funnel_visitors)
        WITH SYNONYMS = ('paywall_seen_pct')
        COMMENT = 'Share of paid visitors who saw the paywall, overall (Paywall seen %).',
    PAYWALL_INTERACTION_RATE AS visitor_funnel.visitors_interacted_paywall / NULLIFZERO(visitor_funnel.funnel_visitors)
        COMMENT = 'Share of paid visitors who clicked the paywall, overall (Paywall interaction %).',
    PAYWALL_CONVERSION_RATE AS visitor_funnel.visitors_converted_via_paywall / NULLIFZERO(visitor_funnel.funnel_visitors)
        COMMENT = 'Share of paid visitors who bought via the paywall, overall (Paywall conversion %).',
    VISITOR_CONVERSION_RATE AS visitor_funnel.visitors_converted / NULLIFZERO(visitor_funnel.funnel_visitors)
        WITH SYNONYMS = ('conversion_rate', 'conversion_pct')
        COMMENT = 'Share of paid visitors who bought a subscription by any route, overall (Conversion %).',
    PAYWALL_CONVERSIONS_PER_PAYWALL_SEEN AS visitor_funnel.visitors_converted_via_paywall / NULLIFZERO(visitor_funnel.visitors_saw_paywall)
        COMMENT = 'Visitors who bought via the paywall per visitor who saw it, overall (Paywall converted / paywall seen).',
    PAYWALL_TO_INTERACTION_RATE AS visitor_funnel.visitors_interacted_paywall / NULLIFZERO(visitor_funnel.visitors_saw_paywall)
        COMMENT = 'Step to step: visitors who clicked the paywall per visitor who saw it, overall.',
    INTERACTION_TO_PURCHASE_RATE AS visitor_funnel.visitors_converted_via_paywall / NULLIFZERO(visitor_funnel.visitors_interacted_paywall)
        COMMENT = 'Step to step: visitors who bought via the paywall per visitor who clicked it, overall.',
    PAYWALL_SEEN_RATE_SAME_VISIT AS visitor_funnel.visitors_saw_paywall_same_visit / NULLIFZERO(visitor_funnel.funnel_visitors)
        COMMENT = 'Share of paid visitors who saw the paywall, in the same visit (Paywall seen %).',
    PAYWALL_INTERACTION_RATE_SAME_VISIT AS visitor_funnel.visitors_interacted_paywall_same_visit / NULLIFZERO(visitor_funnel.funnel_visitors)
        COMMENT = 'Share of paid visitors who clicked the paywall, in the same visit (Paywall interaction %).',
    PAYWALL_CONVERSION_RATE_SAME_VISIT AS visitor_funnel.visitors_converted_via_paywall_same_visit / NULLIFZERO(visitor_funnel.funnel_visitors)
        COMMENT = 'Share of paid visitors who bought via the paywall, in the same visit (Paywall conversion %).',
    VISITOR_CONVERSION_RATE_SAME_VISIT AS visitor_funnel.visitors_converted_same_visit / NULLIFZERO(visitor_funnel.funnel_visitors)
        COMMENT = 'Share of paid visitors who bought a subscription by any route, in the same visit (Conversion %).',
    PAYWALL_CONVERSIONS_PER_PAYWALL_SEEN_SAME_VISIT AS visitor_funnel.visitors_converted_via_paywall_same_visit / NULLIFZERO(visitor_funnel.visitors_saw_paywall_same_visit)
        COMMENT = 'Visitors who bought via the paywall per visitor who saw it, in the same visit (Paywall converted / paywall seen).',
    PAYWALL_TO_INTERACTION_RATE_SAME_VISIT AS visitor_funnel.visitors_interacted_paywall_same_visit / NULLIFZERO(visitor_funnel.visitors_saw_paywall_same_visit)
        COMMENT = 'Step to step: visitors who clicked the paywall per visitor who saw it, in the same visit.',
    INTERACTION_TO_PURCHASE_RATE_SAME_VISIT AS visitor_funnel.visitors_converted_via_paywall_same_visit / NULLIFZERO(visitor_funnel.visitors_interacted_paywall_same_visit)
        COMMENT = 'Step to step: visitors who bought via the paywall per visitor who clicked it, in the same visit.'
)

COMMENT = 'Paid marketing performance: spend, delivery, paid traffic, the paid visitor funnel by stage with LTS and RevOps bands (as on the dashboard''s Funnel tab), and the subscriptions the click-based attribution credits to paid media, by platform, agency, funnel stage and campaign. Matches the Marketing Measurement Dashboard. Built by dbt (model sv_marketing).'

AI_SQL_GENERATION 'The three tables have different grains, so never combine metrics from two of them in one query except by date. Use campaign_days for spend, CPA, cost per arrival, CTR, CPM and anything comparing campaigns, agencies, platforms or funnel stages, including anything that combines spend with traffic, visitor outcomes or subscriptions. Use paid_page_views only to slice traffic by content, device, browser, country, ad name or the page view''s score band; its page_view_spend splits each day''s spend equally across that day''s page views. Use visitor_funnel for every funnel question (visitors, paywall seen, paywall interaction, bought via the paywall, converted, overall or in the same visit, and their rates), including by LTS or RevOps band or landing content pillar; it matches the dashboard''s Funnel tab. It has one row per visitor and stage plus one All stages row per visitor, so always group by or filter visitor_funnel.visitor_funnel_stage, take totals across stages from the All stages rows, and never add the stage rows together. Overall means in any later visit; same visit means in the visit the visitor arrived in. The campaign_days arrivals metrics count a visitor once per campaign, so use them only for cost per arrival and campaign comparisons. For targeting questions use lts_band_on_arrival or revops_band_on_arrival, because scores rise during a visit that ends in a purchase. CPA is spend divided by paid attributed subscriptions (position-based credit from the click-based attribution, on the day of the click). Dates mean different things per table: campaign_days spend and traffic on the day they happened, its visitor outcomes on the day the visitor first arrived from the campaign, and its attributed subscriptions on the day of the click; visitor_funnel on the visitor''s first day in the stage (first paid day for All stages). Spend is in each ad account''s currency: nearly all USD, but a GBP 8ms Meta account until March 2026 and a GBP Meta account without an agency until May 2026 (about 2 percent of spend) are added in as reported. Impressions and clicks are Meta only. Agency values are lower case (8ms, dbs); platform values are meta, google and microsoft; funnel_stage is TOF, MOF or BOF and empty for campaigns without a stage. LTS scores are sparse: Piano scored about 15 to 40 percent of paid page views, and almost none in April and May 2026. Country names are sentence case, for example ''United states''. For a period such as "last month", filter dates.year_month or dates.date_day; data runs to yesterday.'

AI_VERIFIED_QUERIES (
    cpa_by_agency_last_month AS (
        QUESTION 'What was the spend, paid subscriptions and CPA for each agency last month?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS campaign_days.agency METRICS campaign_days.spend, campaign_days.paid_attributed_subscriptions, cpa WHERE dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY spend DESC'
    ),
    spend_and_arrivals_by_platform_by_week AS (
        QUESTION 'How much did we spend and how many visitors arrived on each platform each week over the last eight weeks?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS dates.week_start_date, campaign_days.platform METRICS campaign_days.spend, campaign_days.arrivals, cost_per_arrival WHERE dates.date_day >= DATEADD(WEEK, -8, DATE_TRUNC(WEEK, CURRENT_DATE))) ORDER BY week_start_date, platform'
    ),
    funnel_by_stage_last_month AS (
        QUESTION 'Show the paid visitor funnel by stage for last month: visitors, saw the paywall, interacted with it, bought via the paywall and converted overall, with the rates.'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS visitor_funnel.visitor_funnel_stage METRICS visitor_funnel.funnel_visitors, visitor_funnel.visitors_saw_paywall, visitor_funnel.visitors_interacted_paywall, visitor_funnel.visitors_converted_via_paywall, visitor_funnel.visitors_converted, paywall_seen_rate, paywall_interaction_rate, paywall_conversion_rate, visitor_conversion_rate, paywall_conversions_per_paywall_seen WHERE dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY funnel_visitors DESC'
    ),
    funnel_by_stage_same_visit_last_month AS (
        QUESTION 'Show the paid visitor funnel by stage for last month counting only the same visit.'
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS visitor_funnel.visitor_funnel_stage METRICS visitor_funnel.funnel_visitors, visitor_funnel.visitors_saw_paywall_same_visit, visitor_funnel.visitors_interacted_paywall_same_visit, visitor_funnel.visitors_converted_via_paywall_same_visit, visitor_funnel.visitors_converted_same_visit, paywall_seen_rate_same_visit, visitor_conversion_rate_same_visit WHERE dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY funnel_visitors DESC'
    ),
    bof_funnel_by_lts_band_last_month AS (
        QUESTION 'For BOF last month, how did the funnel vary by LTS band?'
        ONBOARDING_QUESTION TRUE
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS visitor_funnel.lts_band_on_arrival METRICS visitor_funnel.funnel_visitors, visitor_funnel.visitors_saw_paywall, visitor_funnel.visitors_converted, paywall_seen_rate, visitor_conversion_rate WHERE visitor_funnel.visitor_funnel_stage = ''BOF'' AND dates.year_month = TO_CHAR(DATEADD(MONTH, -1, CURRENT_DATE), ''YYYY-MM'')) ORDER BY lts_band_on_arrival'
    ),
    paid_page_views_by_pillar_last_week AS (
        QUESTION 'Which content pillars got the most paid page views last week, and how much spend went to them?'
        SQL 'SELECT * FROM SEMANTIC_VIEW({{ this }} DIMENSIONS paid_page_views.content_pillar METRICS paid_page_views.page_view_count, paid_page_views.page_view_spend WHERE paid_page_views.has_page_view AND dates.week_start_date = DATEADD(WEEK, -1, DATE_TRUNC(WEEK, CURRENT_DATE))) ORDER BY page_view_count DESC'
    )
)
