{{
    config(
        materialized="table",
        tags=["marketing", "dim"]
    )
}}

WITH ads AS (

    SELECT
        ad_id::VARCHAR AS ad_id,
        ad_name,
        ad_set_id::VARCHAR AS adset_id,
        campaign_id::VARCHAR AS campaign_id,
        creative_id::VARCHAR AS creative_id,
        account_id::VARCHAR AS account_id
    FROM {{ ref('stg_facebook_ads__ad_history') }}
    WHERE is_most_recent_record

),

ad_sets AS (

    SELECT
        ad_set_id::VARCHAR AS adset_id,
        ad_set_name AS adset_name
    FROM {{ ref('stg_facebook_ads__ad_set_history') }}
    WHERE is_most_recent_record

),

campaigns AS (

    SELECT
        campaign_id::VARCHAR AS campaign_id,
        campaign_name
    FROM {{ ref('stg_facebook_ads__campaign_history') }}
    WHERE is_most_recent_record

),

creatives AS (

    SELECT
        creative_id::VARCHAR AS creative_id,
        creative_name,
        url AS landing_url,
        at_bbc_team
    FROM {{ ref('int_facebook_ads__creative_history') }}

),

accounts AS (

    SELECT
        account_id::VARCHAR AS account_id,
        account_name,
        currency AS account_currency
    FROM {{ ref('stg_facebook_ads__account_history') }}
    WHERE is_most_recent_record

),

meta_ads AS (

    SELECT
        'meta' AS platform,
        a.ad_id,
        a.ad_name,
        a.adset_id,
        s.adset_name,
        a.campaign_id,
        c.campaign_name,
        a.creative_id,
        cr.creative_name,
        cr.landing_url,
        a.account_id,
        acc.account_name,
        acc.account_currency,
        COALESCE(ma.account_purpose, 'other') AS account_purpose,
        LOWER(NULLIF(TRIM(cr.at_bbc_team), '')) AS bbc_team_from_tag,
        LOWER(REGEXP_SUBSTR(
            UPPER(COALESCE(a.ad_name, '') || ' ' || COALESCE(s.adset_name, '') || ' ' || COALESCE(c.campaign_name, '')),
            '(DBS|8MS)'
        )) AS bbc_team_from_name,
        LOWER(NULLIF(TRIM(ma.default_bbc_team), '')) AS bbc_team_account_default
    FROM ads a
    LEFT JOIN ad_sets s ON a.adset_id = s.adset_id
    LEFT JOIN campaigns c ON a.campaign_id = c.campaign_id
    LEFT JOIN creatives cr ON a.creative_id = cr.creative_id
    LEFT JOIN accounts acc ON a.account_id = acc.account_id
    LEFT JOIN {{ ref('meta_ads_accounts') }} ma ON a.account_id = ma.account_id

),

manual_ads AS (

    SELECT
        IFF(LENGTH(ad_id) = 14, 'microsoft', 'google') AS platform,
        ad_id,
        ad_name,
        adset_name,
        account_id,
        LOWER(REGEXP_SUBSTR(UPPER(ad_name), '(DBS|8MS)')) AS bbc_team_from_name
    FROM {{ ref('stg_google_ads__spend') }}
    -- the latest name; an ad renamed during a day keeps the name on its higher-spend line
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ad_id ORDER BY spend_date DESC, spend_amount DESC, ad_name ASC) = 1

),

resolved AS (

    SELECT
        platform,
        ad_id,
        ad_name,
        adset_id,
        adset_name,
        campaign_id,
        campaign_name,
        creative_id,
        creative_name,
        landing_url,
        account_id,
        account_name,
        account_currency,
        account_purpose,
        COALESCE(bbc_team_from_tag, bbc_team_from_name, bbc_team_account_default) AS bbc_team,
        CASE
            WHEN bbc_team_from_tag IS NOT NULL THEN 'url_tag'
            WHEN bbc_team_from_name IS NOT NULL THEN 'name'
            WHEN bbc_team_account_default IS NOT NULL THEN 'account_default'
        END AS bbc_team_source
    FROM meta_ads

    UNION ALL

    SELECT
        platform,
        ad_id,
        ad_name,
        NULL AS adset_id,
        adset_name,
        NULL AS campaign_id,
        NULL AS campaign_name,
        NULL AS creative_id,
        NULL AS creative_name,
        NULL AS landing_url,
        account_id,
        NULL AS account_name,
        NULL AS account_currency,
        'subscriptions' AS account_purpose,
        bbc_team_from_name AS bbc_team,
        IFF(bbc_team_from_name IS NOT NULL, 'name', NULL) AS bbc_team_source
    FROM manual_ads

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['r.platform', 'r.ad_id']) }} AS ad_sk,
    r.platform,
    r.ad_id,
    r.ad_name,
    r.adset_id,
    r.adset_name,
    r.campaign_id,
    r.campaign_name,
    r.creative_id,
    r.creative_name,
    r.landing_url,
    r.account_id,
    r.account_name,
    r.account_currency,
    r.account_purpose,
    r.bbc_team,
    r.bbc_team_source,
    COALESCE(pa.is_paid_media, FALSE) AS is_paid_media
FROM resolved r
LEFT JOIN {{ ref('bbc_team_agencies') }} pa ON r.bbc_team = pa.bbc_team_raw

UNION ALL

SELECT
    {{ dbt_utils.generate_surrogate_key(["'unknown'"]) }} AS ad_sk,
    'unknown' AS platform,
    'unknown' AS ad_id,
    'Unknown ad' AS ad_name,
    NULL AS adset_id,
    NULL AS adset_name,
    'unknown' AS campaign_id,
    'Unknown campaign' AS campaign_name,
    NULL AS creative_id,
    NULL AS creative_name,
    NULL AS landing_url,
    NULL AS account_id,
    NULL AS account_name,
    NULL AS account_currency,
    'other' AS account_purpose,
    NULL AS bbc_team,
    NULL AS bbc_team_source,
    FALSE AS is_paid_media
