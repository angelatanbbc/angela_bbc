{{ config(materialized="view") }}

SELECT *
FROM {{ ref('int_conversion_attribution') }}
