{{ config(
    materialized='table',
    tags=['piano', 'catalog', 'staging'],
) }}

SELECT
    OFFER_ID AS offer_id,
    NAME AS offer_name,
    STATUS AS offer_status,
    DELETED AS is_deleted,
    CREATE_DATE AS created_at,
    UPDATE_DATE AS updated_at,
    FETCHED_BY_ID AS is_fetched_by_id,
    SNAPSHOT_AT AS snapshot_at,
    SNAPSHOT_DATE AS snapshot_date
FROM {{ source('cgm_extract_load', 'raw_piano_offers') }}
-- Loads are append-only, so keep only the latest load per day.
QUALIFY _DLT_LOAD_ID::FLOAT = MAX(_DLT_LOAD_ID::FLOAT) OVER (PARTITION BY SNAPSHOT_DATE, FETCHED_BY_ID)
