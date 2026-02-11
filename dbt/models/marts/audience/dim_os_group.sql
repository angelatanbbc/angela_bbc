{{ config(materialized="table") }}


SELECT DISTINCT
    {{ dbt_utils.generate_surrogate_key(['os_group']) }} AS os_group_id,
    os_group
FROM {{ ref('fact_visitors_daily') }}
