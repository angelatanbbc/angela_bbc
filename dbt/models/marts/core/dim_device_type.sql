{{
    config(
        materialized="table",
        tags=["mart","core",'dim']
    )
}}


WITH device_types AS (

    SELECT 'Mobile Phone' AS device_type

    UNION ALL

    SELECT 'Desktop' AS device_type

    UNION ALL

    SELECT 'Tablet' AS device_type

    UNION ALL

    SELECT 'Other' AS device_type

    UNION ALL

    SELECT 'Unknown' AS device_type

)

SELECT
    md5(device_type) AS device_type_id,
    device_type
FROM device_types
