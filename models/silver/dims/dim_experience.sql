{{
    config(
        materialized="table",
        tags=['subscriptions', 'piano', 'mart', 'dim']
    )
}}

WITH experiences AS (

    -- Latest state of every experience in the Piano API snapshots: the nightly
    -- list, plus archived experiences backfilled by id, which the list leaves
    -- out. An experience archived after the snapshots began keeps its last
    -- listed state.
    SELECT
        experience_id,
        experience_name,
        experience_description,
        experience_type,
        experience_status,
        is_deleted,
        created_at,
        updated_at,
        NOT is_fetched_by_id
        AND snapshot_date = MAX(IFF(is_fetched_by_id, NULL, snapshot_date)) OVER () AS is_listed_in_piano
    FROM {{ ref('stg_piano__experiences') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY experience_id ORDER BY snapshot_at DESC) = 1

)

SELECT
    experience_id,
    -- Piano's experience type: site and template-interaction experiences run
    -- on the web, mobile ones in the app. A new type is Unknown, not guessed.
    -- Routes events into the web or app exposure and conversion pipelines.
    CASE experience_type
        WHEN 'site' THEN 'Web'
        WHEN 'template-interaction' THEN 'Web'
        WHEN 'mobile' THEN 'Mobile App'
        ELSE 'Unknown'
    END AS app_type,
    experience_name,
    experience_description,
    experience_type,
    experience_status,
    is_deleted,
    is_listed_in_piano,
    created_at,
    updated_at
FROM experiences
