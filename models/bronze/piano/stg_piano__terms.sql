{{ config(
    materialized='table',
    tags=['piano', 'catalog', 'staging'],
) }}

SELECT
    TERM_ID AS term_id,
    NAME AS term_name,
    NULLIF(DESCRIPTION, '') AS term_description,
    TYPE AS term_type,
    TYPE_NAME AS term_type_name,
    RESOURCE_RID AS resource_id,
    RESOURCE_NAME AS resource_name,
    BILLING_CONFIG AS billing_config,
    NULLIF(PRODUCT_CATEGORY, '') AS product_category,
    PAYMENT_BILLING_PLAN AS billing_plan,
    PAYMENT_BILLING_PLAN_DESCRIPTION AS billing_plan_description,
    TRY_PARSE_JSON(PAYMENT_BILLING_PLAN_TABLE) AS billing_plan_steps,
    PAYMENT_CURRENCY AS currency_code,
    PAYMENT_FIRST_PRICE AS first_price_amount,
    PAYMENT_IS_SUBSCRIPTION AS is_subscription,
    PAYMENT_HAS_FREE_TRIAL AS has_free_trial,
    PAYMENT_NEW_CUSTOMERS_ONLY AS is_new_customers_only,
    PAYMENT_TRIAL_NEW_CUSTOMERS_ONLY AS is_trial_new_customers_only,
    PAYMENT_FORCE_AUTO_RENEW AS is_auto_renew_forced,
    PAYMENT_ALLOW_GIFT AS is_gift_allowed,
    PAYMENT_RENEW_GRACE_PERIOD AS renew_grace_period_days,
    SHARED_ACCOUNT_COUNT AS shared_account_count,
    EXTERNAL_API_ID AS external_api_id,
    EXTERNAL_API_NAME AS external_api_name,
    NULLIF(EVT_ITUNES_PRODUCT_ID, '') AS itunes_product_id,
    NULLIF(EVT_GOOGLE_PLAY_PRODUCT_ID, '') AS google_play_product_id,
    CREATE_DATE AS created_at,
    UPDATE_DATE AS updated_at,
    FETCHED_BY_ID AS is_fetched_by_id,
    SNAPSHOT_AT AS snapshot_at,
    SNAPSHOT_DATE AS snapshot_date
FROM {{ source('cgm_extract_load', 'raw_piano_terms') }}
-- Loads are append-only, so keep only the latest load per day.
QUALIFY _DLT_LOAD_ID::FLOAT = MAX(_DLT_LOAD_ID::FLOAT) OVER (PARTITION BY SNAPSHOT_DATE, FETCHED_BY_ID)
