{{
    config(
        materialized="table",
        tags=["fct", "marketing"]
    )
}}

SELECT
    -- keys
    {{ dbt_utils.generate_surrogate_key(['platform', 'account_id', 'ad_id', 'spend_date']) }} AS ad_performance_sk,
    {{ dbt_utils.generate_surrogate_key(['platform', 'ad_id']) }} AS ad_sk,
    platform,
    account_id,
    ad_id,
    adset_id,
    campaign_id,

    -- dates
    spend_date,

    -- attributes
    account_currency,

    -- measures (reach and frequency are not additive across days or ads)
    COALESCE(impressions, 0) AS impressions,
    COALESCE(clicks, 0) AS link_clicks,
    COALESCE(spend_amount, 0) AS spend_amount,
    reach,
    frequency
FROM {{ ref('int_marketing__ad_spend_daily') }}
