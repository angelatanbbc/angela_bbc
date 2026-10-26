{{
    config(
        materialized="table",
        tags=["marketing", "intermediate"]
    )
}}

/*
Ad spend: one row per platform x account x ad x day. Meta comes from the facebook_ads package's
basic_ad report; Google and Microsoft from the manual upload, which has no account, hierarchy or
delivery metrics (an ad renamed during a day is summed onto one row under its higher-spend name).
Spend is never split per visit or visitor here.
*/

WITH meta_spend AS (

    SELECT
        ad_id::VARCHAR AS ad_id,
        account_id::VARCHAR AS account_id,
        date_day AS spend_date,
        ad_name,
        ad_set_name AS adset_name,
        impressions,
        clicks,
        reach,
        frequency,
        spend
    FROM {{ ref('stg_facebook_ads__basic_ad') }}
    WHERE date_day >= '{{ var("marketing_start_date") }}'

),

meta_ads AS (

    SELECT
        ad_id,
        adset_id,
        adset_name,
        campaign_id,
        campaign_name,
        ad_name,
        bbc_team,
        bbc_team_source,
        is_podcast_ad
    FROM {{ ref('dim_ad') }}
    WHERE platform = 'meta'

),

meta_accounts AS (

    SELECT
        account_id::VARCHAR AS account_id,
        account_name,
        currency AS account_currency
    FROM {{ ref('stg_facebook_ads__account_history') }}
    WHERE is_most_recent_record

),

manual_spend AS (

    SELECT
        ad_id,
        spend_date,
        MAX(account_id) AS account_id,
        MAX_BY(ad_name, spend_amount) AS ad_name,
        MAX(adset_name) AS adset_name,
        SUM(spend_amount) AS spend
    FROM {{ ref('stg_google_ads__spend') }}
    GROUP BY ad_id, spend_date

),

meta AS (

    SELECT
        'meta' AS platform,
        s.account_id,
        acc.account_name,
        acc.account_currency,
        COALESCE(ma.account_purpose, 'other') AS account_purpose,
        h.campaign_id,
        h.campaign_name,
        h.adset_id,
        COALESCE(h.adset_name, s.adset_name) AS adset_name,
        s.ad_id,
        COALESCE(h.ad_name, s.ad_name) AS ad_name,
        COALESCE(h.bbc_team, LOWER(NULLIF(TRIM(ma.default_bbc_team), ''))) AS bbc_team,
        CASE
            WHEN h.bbc_team IS NOT NULL THEN h.bbc_team_source
            WHEN NULLIF(TRIM(ma.default_bbc_team), '') IS NOT NULL THEN 'account_default'
        END AS bbc_team_source,
        COALESCE(h.is_podcast_ad, s.ad_name ILIKE '{{ var("podcast_ad_name_pattern") }}', FALSE) AS is_podcast_ad,
        s.spend_date,
        s.impressions,
        s.clicks,
        s.reach,
        s.frequency,
        s.spend
    FROM meta_spend s
    LEFT JOIN meta_ads h ON s.ad_id = h.ad_id
    LEFT JOIN meta_accounts acc ON s.account_id = acc.account_id
    LEFT JOIN {{ ref('meta_ads_accounts') }} ma ON s.account_id = ma.account_id

),

manual AS (

    SELECT
        IFF(LENGTH(ad_id) = 14, 'microsoft', 'google') AS platform,
        account_id,
        NULL::VARCHAR AS account_name,
        NULL::VARCHAR AS account_currency,
        'subscriptions' AS account_purpose,
        NULL::VARCHAR AS campaign_id,
        NULL::VARCHAR AS campaign_name,
        NULL::VARCHAR AS adset_id,
        adset_name,
        ad_id,
        ad_name,
        LOWER(REGEXP_SUBSTR(UPPER(ad_name), '(DBS|8MS)')) AS bbc_team,
        IFF(REGEXP_SUBSTR(UPPER(ad_name), '(DBS|8MS)') IS NOT NULL, 'name', NULL) AS bbc_team_source,
        FALSE AS is_podcast_ad,
        spend_date,
        NULL::NUMBER(18, 0) AS impressions,
        NULL::NUMBER(18, 0) AS clicks,
        NULL::NUMBER(18, 0) AS reach,
        NULL::NUMBER(18, 6) AS frequency,
        spend
    FROM manual_spend

)

SELECT
    platform,
    account_id,
    account_name,
    account_currency,
    account_purpose,
    campaign_id,
    campaign_name,
    adset_id,
    adset_name,
    ad_id,
    ad_name,
    bbc_team,
    bbc_team_source,
    is_podcast_ad,
    spend_date,
    impressions,
    clicks,
    reach,
    frequency,
    spend AS spend_amount
FROM meta

UNION ALL

SELECT
    platform,
    account_id,
    account_name,
    account_currency,
    account_purpose,
    campaign_id,
    campaign_name,
    adset_id,
    adset_name,
    ad_id,
    ad_name,
    bbc_team,
    bbc_team_source,
    is_podcast_ad,
    spend_date,
    impressions,
    clicks,
    reach,
    frequency,
    spend AS spend_amount
FROM manual
