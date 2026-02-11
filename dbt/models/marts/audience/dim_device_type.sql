{{ config(materialized="table") }}


SELECT DISTINCT
    {{ dbt_utils.generate_surrogate_key(['device_type']) }} AS device_type_id,
    device_type
FROM {{ ref('fact_visitors_daily') }}
