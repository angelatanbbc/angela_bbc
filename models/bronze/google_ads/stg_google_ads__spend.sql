{{
    config(
        materialized="view"
    )
}}

SELECT
    -- Performance Max lines have no ad id; they are kept under their campaign so their spend isn't lost
    COALESCE(AD_ID::VARCHAR, 'campaign:' || AD_NAME) AS ad_id,
    TRY_TO_DATE(DATE, 'DD/MM/YYYY') AS spend_date,
    ACCOUNT_ID::VARCHAR AS account_id,
    AD_NAME AS ad_name,
    ADSET_NAME AS adset_name,
    SPEND::NUMBER(18, 4) AS spend_amount
FROM {{ source('GOOGLE_ADS', 'STG_GOOGLE_ADS') }}
WHERE
    TRY_TO_DATE(DATE, 'DD/MM/YYYY') IS NOT NULL
    AND COALESCE(AD_ID::VARCHAR, AD_NAME) IS NOT NULL
