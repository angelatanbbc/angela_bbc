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
    -- Piano's experience type: mobile experiences run in the app, site and
    -- template-interaction ones on the web. Routes events into the web or app
    -- exposure and conversion pipelines. This is the experience surface, not
    -- the device platform (dim_device_platform) or the billing channel
    -- (dim_term.billing_channel).
    experience_type = 'mobile' AS is_app_experience,
    experience_name,
    experience_description,
    experience_type,
    experience_status,
    is_deleted,
    is_listed_in_piano,
    created_at,
    updated_at
FROM experiences
