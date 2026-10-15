{{
    config(
        materialized="table",
        tags=["marketing", "dim"]
    )
}}

WITH tag_sets AS (

    SELECT DISTINCT
        campaign_tracking_sk,
        campaign,
        ad_set_name,
        ad_set_id,
        creative_id,
        creation,
        objective,
        medium,
        keyword,
        match_type,
        campaign_type,
        ad_format,
        link_origin,
        at_campaign_name
    FROM {{ ref('int_attribution__journey_touches') }}
    WHERE campaign_tracking_sk != {{ dbt_utils.generate_surrogate_key(["'none'"]) }}

)

SELECT
    campaign_tracking_sk,
    TRUE AS has_tags,
    campaign,
    ad_set_name,
    ad_set_id,
    creative_id,
    creation,
    objective,
    medium,
    keyword,
    match_type,
    campaign_type,
    ad_format,
    link_origin,
    at_campaign_name
FROM tag_sets

UNION ALL

SELECT
    {{ dbt_utils.generate_surrogate_key(["'none'"]) }} AS campaign_tracking_sk,
    FALSE AS has_tags,
    NULL AS campaign,
    NULL AS ad_set_name,
    NULL AS ad_set_id,
    NULL AS creative_id,
    NULL AS creation,
    NULL AS objective,
    NULL AS medium,
    NULL AS keyword,
    NULL AS match_type,
    NULL AS campaign_type,
    NULL AS ad_format,
    NULL AS link_origin,
    NULL AS at_campaign_name
