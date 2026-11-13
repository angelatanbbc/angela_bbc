{{ config(
    materialized='table',
    tags=['piano', 'subscription', 'snapshots', 'staging', 'joseph.iles@bbc.com'],
) }}

SELECT
    SUBSCRIPTION_ID AS subscription_id,
    USER_UID AS user_uid,
    STATUS AS status,
    STATUS_NAME AS status_name,
    STATUS_NAME_IN_REPORTS AS status_name_in_reports,
    AUTO_RENEW AS auto_renew,
    CANCELABLE AS cancellable,
    CANCELABLE_AND_REFUNDADLE AS cancellable_and_refundable,
    BILLING_PLAN AS billing_plan,
    TERM_TERM_ID AS term_id,
    TERM_NAME AS term_name,
    RESOURCE_RID AS resource_rid,
    RESOURCE_NAME AS resource_name,
    START_DATE AS start_date,
    END_DATE AS end_date,
    NEXT_BILL_DATE AS next_bill_date,
    NEXT_VERIFICAITION_DATE AS next_verification_date,
    IS_IN_TRIAL AS is_in_trial,
    TRIAL_PERIOD_END_DATE AS trial_period_end_date,
    TRIAL_AMOUNT AS trial_amount,
    TRIAL_CURRENCY AS trial_currency,
    CHARGE_COUNT AS charge_count,
    CONVERSION_RESULT AS conversion_result,
    ACQUISITION_TYPE AS acquisition_type,
    EXTERNAL_API_NAME AS external_api_name,
    USER_CREATE_DATE AS user_create_date,
    USER_LAST_VISIT AS user_last_visit,
    SNAPSHOT_AT AS snapshot_at,
    SNAPSHOT_DATE AS snapshot_date
FROM {{ source('cgm_extract_load', 'raw_piano_subscription_snapshots') }}
-- Loads are append-only, so keep only the latest load per day. Backfilled
-- legacy rows have load id 0, so a real load wins wherever both exist.
QUALIFY _DLT_LOAD_ID::FLOAT = MAX(_DLT_LOAD_ID::FLOAT) OVER (PARTITION BY SNAPSHOT_DATE)
