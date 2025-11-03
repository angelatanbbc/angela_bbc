{{ config(materialized="table") }}

SELECT
    experience_id,
    ANY_VALUE(experience_name) AS experience_name
FROM {{ ref('stg_piano_events__exposures') }}
WHERE experience_id IS NOT NULL
GROUP BY experience_id
