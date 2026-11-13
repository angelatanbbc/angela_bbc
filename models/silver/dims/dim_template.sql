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
    t.template_id,
    t.template_name,
    -- Overrides first, for templates whose name does not say what they are.
    COALESCE(
        o.template_type,
        CASE
            WHEN t.template_name ILIKE '%gate%' THEN 'Paywall'
            WHEN t.template_name ILIKE '%ribbon%' THEN 'Ribbon'
            WHEN t.template_name ILIKE '%landing%page%' THEN 'Subscription Landing Page'
            ELSE 'Other'
        END
    ) AS template_type,
    t.template_description,
    t.template_piano_type_id,
    t.template_category_id,
    t.template_status,
    t.is_published,
    t.is_deleted,
    t.is_listed_in_piano,
    t.created_at,
    t.updated_at,
    t.archived_at
FROM templates t
LEFT JOIN {{ ref('template_type_override') }} o
    ON t.template_id = o.template_id
