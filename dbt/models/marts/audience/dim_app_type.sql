{{ config(materialized="table") }}


SELECT DISTINCT
    {{ dbt_utils.generate_surrogate_key(['app_type']) }} AS app_type_id,
    app_type
FROM {{ ref('fact_visitors_daily') }}
