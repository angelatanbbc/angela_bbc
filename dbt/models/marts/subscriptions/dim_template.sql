{{ config(materialized="table") }}

WITH template_ids AS (
    SELECT DISTINCT template_id
    FROM {{ ref('stg_piano_events__exposures') }}
    WHERE template_id IS NOT NULL
)

SELECT
    id.template_id,
    map.template_name,
    map.template_category
FROM template_ids id
LEFT JOIN {{ ref('template_mapping') }} map
    ON id.template_id = map.template_id
