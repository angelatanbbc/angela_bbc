{{ config(
    materialized='table',
    tags=['piano', 'catalog', 'staging'],
) }}

SELECT
    EXPERIENCE_ID AS experience_id,
    TITLE AS experience_name,
    NULLIF(DESCRIPTION, '') AS experience_description,
    TYPE AS experience_type,
    -- The list endpoint returns LIVE, OFFLINE, ...; experience/get returns lower case.
    UPPER(STATUS) AS experience_status,
    HIERARCHY_TYPE AS hierarchy_type,
    NULLIF(PARENT_ID, '') AS parent_experience_id,
    TRY_PARSE_JSON(SCHEDULE) AS schedule,
    -- experience/get has no deleted field; Piano reports a deleted experience
    -- as archived, and the nightly list never includes archived ones.
    COALESCE(DELETED, UPPER(STATUS) = 'ARCHIVED') AS is_deleted,
    MAJOR_VERSION AS major_version,
    MINOR_VERSION AS minor_version,
    CREATE_DATE AS created_at,
    UPDATE_DATE AS updated_at,
    FETCHED_BY_ID AS is_fetched_by_id,
    SNAPSHOT_AT AS snapshot_at,
    SNAPSHOT_DATE AS snapshot_date
FROM {{ source('cgm_extract_load', 'raw_piano_experiences') }}
-- Loads are append-only, so keep only the latest nightly load per day. Rows
-- backfilled by id (cgm-extract-load backfill-piano-catalog) are kept per record,
-- so a backfill never replaces that day's nightly snapshot or another backfill.
QUALIFY
    _DLT_LOAD_ID::FLOAT = MAX(_DLT_LOAD_ID::FLOAT) OVER (
        PARTITION BY SNAPSHOT_DATE, FETCHED_BY_ID, IFF(FETCHED_BY_ID, EXPERIENCE_ID, NULL)
    )
