{{ config(
    materialized='table',
    tags=['piano', 'catalog', 'staging'],
) }}

SELECT
    OFFER_TEMPLATE_ID AS template_id,
    NAME AS template_name,
    NULLIF(DESCRIPTION, '') AS template_description,
    TYPE AS template_piano_type,
    TYPE_ID AS template_piano_type_id,
    CATEGORY_ID AS template_category_id,
    STATUS AS template_status,
    BOILERPLATE_TYPE AS boilerplate_type,
    BOILERPLATE_TYPE_ID AS boilerplate_type_id,
    TOKEN_TYPE AS token_type,
    ENGINE AS engine,
    IS_PUBLISHED AS is_published,
    IS_GLOBAL AS is_global,
    DELETED AS is_deleted,
    VERSION AS template_version,
    COUNT_VARIANTS AS variant_count,
    PUBLISH_DATE AS published_at,
    CREATE_DATE AS created_at,
    UPDATE_DATE AS updated_at,
    ARCHIVED_DATE AS archived_at,
    FETCHED_BY_ID AS is_fetched_by_id,
    SNAPSHOT_AT AS snapshot_at,
    SNAPSHOT_DATE AS snapshot_date
FROM {{ source('cgm_extract_load', 'raw_piano_offer_templates') }}
-- Loads are append-only, so keep only the latest nightly load per day. Rows
-- backfilled by id (cgm-extract-load backfill-piano-catalog) are kept per record,
-- so a backfill never replaces that day's nightly snapshot or another backfill.
QUALIFY
    _DLT_LOAD_ID::FLOAT = MAX(_DLT_LOAD_ID::FLOAT) OVER (
        PARTITION BY SNAPSHOT_DATE, FETCHED_BY_ID, IFF(FETCHED_BY_ID, OFFER_TEMPLATE_ID, NULL)
    )
