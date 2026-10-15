{{
    config(
        materialized="table",
        tags=['subscriptions', 'piano', 'mart', 'dim']
    )
}}

WITH templates AS (

    -- Latest state of every offer template in the Piano API snapshots: the
    -- nightly list (including archived templates), plus system templates
    -- backfilled by id, which the list leaves out.
    SELECT
        template_id,
        template_name,
        template_description,
        template_piano_type_id,
        template_category_id,
        template_status,
        is_published,
        is_deleted,
        created_at,
        updated_at,
        archived_at,
        NOT is_fetched_by_id
        AND snapshot_date = MAX(IFF(is_fetched_by_id, NULL, snapshot_date)) OVER () AS is_listed_in_piano
    FROM {{ ref('stg_piano__offer_templates') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY template_id ORDER BY snapshot_at DESC) = 1

)

SELECT
    template_id,
    template_name,
    CASE
        WHEN template_name ILIKE '%gate%' THEN 'Paywall'
        WHEN template_name ILIKE '%ribbon%' THEN 'Ribbon'
        WHEN template_name ILIKE '%landing%page%' THEN 'Subscription Landing Page'
        ELSE 'Other'
    END AS template_type,
    template_description,
    template_piano_type_id,
    template_category_id,
    template_status,
    is_published,
    is_deleted,
    is_listed_in_piano,
    created_at,
    updated_at,
    archived_at
FROM templates
