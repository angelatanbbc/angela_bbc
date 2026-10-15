{{
    config(
        materialized="table",
        tags=["mart", "core", "dim"]
    )
}}

-- Conformed platform dimension: one row per combination of app type, device
-- type and operating system group (4 x 5 x 9 = 180 rows). Static, so every
-- device_platform_id derived from an event with generate_device_platform_id
-- resolves to a row.
WITH app_types AS (

    SELECT column1 AS app_type
    FROM VALUES ('Web'), ('Mobile App'), ('Other'), ('Unknown')

),

device_types AS (

    SELECT column1 AS device_type
    FROM VALUES ('Mobile Phone'), ('Desktop'), ('Tablet'), ('Other'), ('Unknown')

),

os_groups AS (

    SELECT column1 AS os_group
    FROM VALUES ('iOS'), ('iPadOS'), ('macOS'), ('Windows'), ('Linux'), ('Android'), ('Chrome OS'), ('Other'), ('Unknown')

),

combinations AS (

    SELECT
        a.app_type,
        d.device_type,
        o.os_group
    FROM app_types a
    CROSS JOIN device_types d
    CROSS JOIN os_groups o

)

SELECT
    {{ generate_device_platform_id('app_type', 'device_type', 'os_group') }} AS device_platform_id,
    -- Reporting label: the app split by OS, the web split by device
    CASE
        WHEN app_type = 'Mobile App' AND os_group IN ('iOS', 'iPadOS') THEN 'iOS App'
        WHEN app_type = 'Mobile App' AND os_group = 'Android' THEN 'Android App'
        WHEN app_type = 'Mobile App' THEN 'Other App'
        WHEN app_type = 'Web' AND device_type = 'Mobile Phone' THEN 'Mobile Web'
        WHEN app_type = 'Web' AND device_type = 'Tablet' THEN 'Tablet Web'
        WHEN app_type = 'Web' AND device_type = 'Desktop' THEN 'Desktop Web'
        WHEN app_type = 'Web' THEN 'Other Web'
        ELSE 'Unknown'
    END AS platform,
    app_type,
    device_type,
    os_group
FROM combinations
