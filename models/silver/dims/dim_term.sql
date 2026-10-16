{{
    config(
        materialized="table",
        tags=['subscriptions', 'piano', 'mart', 'dim']
    )
}}

WITH terms AS (

    -- Latest state of every term in the Piano API snapshots.
    SELECT
        term_id,
        term_name,
        term_description,
        term_type,
        resource_id,
        resource_name,
        billing_plan_description,
        currency_code,
        first_price_amount,
        -- The last billing step is the price the term renews at; earlier
        -- steps are introductory prices.
        GET(billing_plan_steps, ARRAY_SIZE(billing_plan_steps) - 1) AS recurring_step,
        is_subscription,
        has_free_trial,
        is_trial_new_customers_only,
        external_api_name,
        created_at,
        updated_at,
        NOT is_fetched_by_id
        AND snapshot_date = MAX(IFF(is_fetched_by_id, NULL, snapshot_date)) OVER () AS is_listed_in_piano
    FROM {{ ref('stg_piano__terms') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY term_id ORDER BY snapshot_at DESC) = 1

)

SELECT
    t.term_id,
    t.term_name,
    t.term_description,
    t.term_type,
    t.resource_id,
    t.resource_name,
    -- App store terms are billed by the store, so Piano has no billing plan
    -- for them; their period comes from a seed.
    COALESCE(t.recurring_step:billingPeriod::STRING, s.billing_period) AS billing_period,
    t.billing_plan_description,
    t.currency_code,
    t.first_price_amount,
    t.recurring_step:priceValue::FLOAT AS recurring_price_amount,
    -- Group and business plans cover several people, so count as several
    -- subscriptions; weights come from a seed.
    COALESCE(w.subscription_weight, 1) AS subscription_weight,
    t.is_subscription,
    t.has_free_trial,
    t.is_trial_new_customers_only,
    t.external_api_name,
    t.is_listed_in_piano,
    t.created_at,
    t.updated_at
FROM terms t
LEFT JOIN {{ ref('app_store_term_billing_period') }} s
    ON t.term_id = s.term_id
LEFT JOIN {{ ref('term_subscription_weight') }} w
    ON t.term_id = w.term_id
