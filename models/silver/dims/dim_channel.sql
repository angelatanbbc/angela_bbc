{{
    config(
        materialized="table",
        tags=["marketing", "dim"]
    )
}}

WITH combinations AS (

    SELECT DISTINCT
        channel_sk,
        attribution_source,
        attribution_source_detail,
        piano_source,
        piano_source_detail,
        organic_source,
        organic_source_detail,
        bbc_team,
        partner
    FROM {{ ref('int_attribution__touchpoints_source_imputed') }}

),

described AS (

    SELECT
        c.channel_sk,
        COALESCE(g.channel_group, c.attribution_source) AS channel_group,
        c.attribution_source,
        c.attribution_source_detail,
        c.piano_source,
        c.piano_source_detail,
        c.organic_source,
        c.organic_source_detail,
        c.bbc_team,
        a.agency,
        c.partner,
        COALESCE(a.is_paid_media, FALSE) AS is_paid_media
    FROM combinations c
    LEFT JOIN {{ ref('traffic_source_channels') }} g ON c.attribution_source = g.attribution_source
    LEFT JOIN {{ ref('bbc_team_agencies') }} a
        ON LOWER(c.bbc_team) = a.bbc_team_raw
        AND a.is_paid_media

)

SELECT
    channel_sk,
    channel_group,
    attribution_source,
    attribution_source_detail,
    piano_source,
    piano_source_detail,
    organic_source,
    organic_source_detail,
    bbc_team,
    agency,
    partner,
    is_paid_media
FROM described

UNION ALL

SELECT
    {{ dbt_utils.generate_surrogate_key(["'unknown'"]) }} AS channel_sk,
    'Unknown' AS channel_group,
    'Unknown' AS attribution_source,
    'Unknown' AS attribution_source_detail,
    NULL AS piano_source,
    NULL AS piano_source_detail,
    NULL AS organic_source,
    NULL AS organic_source_detail,
    NULL AS bbc_team,
    NULL AS agency,
    NULL AS partner,
    FALSE AS is_paid_media
