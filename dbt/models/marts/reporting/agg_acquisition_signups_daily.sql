{{ config(
    materialized='table',
    tags=['subscriptions', 'piano', 'tableau'],
) }}

WITH conversions AS (

    SELECT
        conversion_date,
        conversion_id,
        attribution_source,
        COALESCE(billing_period, 'Unknown') AS billing_period,
        experience_id,
        template_id,
        geo_id,
        geo_country,
        geo_region,
        app_type_id,
        device_type_id,
        os_group_id,
        position_weight
    FROM {{ ref('fact_conversions') }}

),

-- position_weight sums to 1 per conversion_id, so n_signups is fully additive:
-- Organic + Paid slices total exactly to the distinct conversion count at any grain.
aggregated AS (

    SELECT
        conversion_date,
        attribution_source,
        billing_period,
        experience_id,
        template_id,
        geo_id,
        geo_country,
        geo_region,
        app_type_id,
        device_type_id,
        os_group_id,
        SUM(position_weight)::NUMBER(38, 6) AS n_signups
    FROM conversions
    GROUP BY ALL

)

SELECT
    {{ dbt_utils.generate_surrogate_key([
        'a.conversion_date',
        'a.attribution_source',
        'a.billing_period',
        'a.geo_id',
        'a.experience_id',
        'a.template_id',
        'a.app_type_id',
        'a.device_type_id',
        'a.os_group_id'
    ]) }} AS signup_day_key,
    a.conversion_date,
    a.attribution_source,
    a.billing_period,
    a.experience_id,
    e.experience_name,
    a.template_id,
    t.template_name,
    t.template_type,
    a.geo_id,
    a.geo_country,
    a.geo_region,
    a.app_type_id,
    at.app_type,
    a.device_type_id,
    dt.device_type,
    a.os_group_id,
    og.os_group,
    a.n_signups
FROM aggregated a
LEFT JOIN {{ ref('dim_experience') }} e
    ON a.experience_id = e.experience_id
LEFT JOIN {{ ref('dim_template') }} t
    ON a.template_id = t.template_id
LEFT JOIN {{ ref('dim_app_type') }} at
    ON a.app_type_id = at.app_type_id
LEFT JOIN {{ ref('dim_device_type') }} dt
    ON a.device_type_id = dt.device_type_id
LEFT JOIN {{ ref('dim_os_group') }} og
    ON a.os_group_id = og.os_group_id
