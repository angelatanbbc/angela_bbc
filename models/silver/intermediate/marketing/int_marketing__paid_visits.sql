{{
    config(
        materialized="table",
        tags=["marketing", "intermediate"]
    )
}}

/*
Paid visits: one row per visit whose agency is a paid-media agency (seed bbc_team_agencies).

The attribution's agency rule at visit level (Piano's src_* columns are constant within a visit):
the visit's own tag (src_bbc_team, else the landing URL's at_bbc_team); with neither, the agency of
its Meta ad (dim_ad), else an 8ms_ / dbs_ campaign name on a Facebook or Instagram visit.
agency_resolved_from says which.
*/

WITH visits AS (

    SELECT
        visit_id,
        COALESCE(
            NULLIF(REGEXP_REPLACE(LOWER(TRIM(MAX(src_bbc_team))), '[?&].*$', ''), ''),
            NULLIF(REGEXP_REPLACE(LOWER(TRIM(MAX(url_at_bbc_team))), '[?&].*$', ''), ''),
            {{ bbc_team_from_campaign('MAX(src_ptr_name)', 'MAX(src_detail)', 'MAX(src_campaign)') }}
        ) AS bbc_team,
        COALESCE(
            NULLIF(TRIM(MAX(src_bbc_team)), '') IS NULL
            AND NULLIF(TRIM(MAX(url_at_bbc_team)), '') IS NULL
            AND {{ bbc_team_from_campaign('MAX(src_ptr_name)', 'MAX(src_detail)', 'MAX(src_campaign)') }} IS NOT NULL,
            FALSE
        ) AS is_bbc_team_from_campaign_name,
        -- digits only: Piano sometimes records Meta's unsubstituted ad id placeholder
        COALESCE(
            MAX(IFF(REGEXP_LIKE(src_creative_id, '^[0-9]+$'), src_creative_id, NULL)),
            MAX(IFF(REGEXP_LIKE(url_at_creative_id, '^[0-9]+$'), url_at_creative_id, NULL))
        ) AS ad_id,
        MAX(src_campaign) AS src_campaign,
        MAX_BY(visit_bounce, page_view_time) AS visit_bounce
    FROM {{ ref('int_piano__page_views') }}
    WHERE visit_id IS NOT NULL
    GROUP BY visit_id

),

paid_agencies AS (

    SELECT
        bbc_team_raw,
        agency
    FROM {{ ref('bbc_team_agencies') }}
    WHERE is_paid_media

),

meta_ads AS (

    SELECT
        ad_id,
        ad_sk,
        LOWER(bbc_team) AS bbc_team
    FROM {{ ref('dim_ad') }}
    WHERE platform = 'meta'

),

visit_agency AS (

    SELECT
        v.visit_id,
        v.ad_id,
        a.ad_sk,
        v.src_campaign,
        v.visit_bounce,
        IFF(v.is_bbc_team_from_campaign_name, NULL, NULLIF(LOWER(TRIM(v.bbc_team)), '')) AS tag_team,
        IFF(pa.bbc_team_raw IS NOT NULL, a.bbc_team, NULL) AS ad_team,
        IFF(v.is_bbc_team_from_campaign_name, NULLIF(LOWER(TRIM(v.bbc_team)), ''), NULL) AS campaign_name_team
    FROM visits v
    LEFT JOIN meta_ads a ON v.ad_id = a.ad_id
    LEFT JOIN paid_agencies pa ON a.bbc_team = pa.bbc_team_raw

)

SELECT
    va.visit_id,
    va.ad_sk,
    va.ad_id,
    pa.agency,
    CASE
        WHEN va.tag_team IS NOT NULL THEN 'visit_tag'
        WHEN va.ad_team IS NOT NULL THEN 'ad_id'
        ELSE 'campaign_name'
    END AS agency_resolved_from,
    va.src_campaign,
    va.visit_bounce
FROM visit_agency va
JOIN paid_agencies pa ON COALESCE(va.tag_team, va.ad_team, va.campaign_name_team) = pa.bbc_team_raw
