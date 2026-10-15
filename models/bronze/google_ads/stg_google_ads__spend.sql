{{
    config(
        materialized="view"
    )
}}

-- dev roles can't read the live schema the upload sits in, so dev builds an empty view unless
-- --vars '{read_google_ads_upload: true}'; remove the switch once dev is granted access
{%- if var('read_google_ads_upload', target.name != 'dev') %}

SELECT
    AD_ID::VARCHAR AS ad_id,
    TRY_TO_DATE(DATE, 'DD/MM/YYYY') AS spend_date,
    ACCOUNT_ID::VARCHAR AS account_id,
    AD_NAME AS ad_name,
    ADSET_NAME AS adset_name,
    SPEND::NUMBER(18, 4) AS spend_amount
FROM {{ source('GOOGLE_ADS', 'STG_GOOGLE_ADS') }}
WHERE
    TRY_TO_DATE(DATE, 'DD/MM/YYYY') IS NOT NULL
    AND AD_ID IS NOT NULL

{%- else %}

SELECT
    NULL::VARCHAR AS ad_id,
    NULL::DATE AS spend_date,
    NULL::VARCHAR AS account_id,
    NULL::VARCHAR AS ad_name,
    NULL::VARCHAR AS adset_name,
    NULL::NUMBER(18, 4) AS spend_amount
WHERE FALSE

{%- endif %}
