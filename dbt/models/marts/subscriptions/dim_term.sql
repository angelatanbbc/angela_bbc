{{ config(materialized="table") }}

SELECT *
FROM {{ ref('term_mapping') }}
