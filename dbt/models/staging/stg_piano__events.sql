{{ config(materialized="view") }}

SELECT *
FROM {{ source('studios_piano', 'studios_piano_events') }}
WHERE site_id = 638824
