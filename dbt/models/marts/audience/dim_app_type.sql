{{ config(materialized="table") }}

WITH app_types AS (

    SELECT 'Web' AS app_type

    UNION ALL

    SELECT 'Mobile App' AS app_type

    UNION ALL

    SELECT 'Other' AS app_type

    UNION ALL

    SELECT 'Unknown' AS app_type

)

SELECT
    md5(app_type) AS app_type_id,
    app_type
FROM app_types
