{{
    config(
        materialized='table',
        tags=['subscriptions', 'piano', 'tableau']
    )
}}

WITH conversions AS (

    SELECT
        conversion_date,
        conversion_id,
        COALESCE(billing_period, 'Unknown') AS billing_period,
        experience_id,
        template_id,
        geo_id,
        geo_country,
        geo_region,
        device_platform_id,
        paid_attribution_weight
    FROM {{ ref('fct_conversions') }}

),

-- each conversion splits into a Paid row (its paid_attribution_weight) and an Organic row (the rest),
-- so n_signups is fully additive: Organic + Paid total exactly to the conversion count at any grain
attributed AS (

    SELECT
        conversion_date,
        'Paid' AS attribution_source,
        billing_period,
        experience_id,
        template_id,
        geo_id,
        geo_country,
        geo_region,
        device_platform_id,
        paid_attribution_weight AS attribution_weight
    FROM conversions
    WHERE paid_attribution_weight > 0

    UNION ALL

    SELECT
        conversion_date,
        'Organic' AS attribution_source,
        billing_period,
        experience_id,
        template_id,
        geo_id,
        geo_country,
        geo_region,
        device_platform_id,
        1 - paid_attribution_weight AS attribution_weight
    FROM conversions
    WHERE paid_attribution_weight < 1

),

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
        device_platform_id,
        SUM(attribution_weight)::NUMBER(38, 6) AS n_signups
    FROM attributed
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
        'a.device_platform_id'
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
    a.device_platform_id,
    dp.platform,
    dp.app_type,
    dp.device_type,
    dp.os_group,
    a.n_signups
FROM aggregated a
LEFT JOIN {{ ref('dim_experience') }} e
    ON a.experience_id = e.experience_id
LEFT JOIN {{ ref('dim_template') }} t
    ON a.template_id = t.template_id
LEFT JOIN {{ ref('dim_device_platform') }} dp
    ON a.device_platform_id = dp.device_platform_id
