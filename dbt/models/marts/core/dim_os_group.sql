{{
    config(
        materialized="table",
        tags=["mart","core",'dim']
    )
}}

WITH os_groups AS (

    SELECT 'iOS' AS os_group

    UNION ALL

    SELECT 'macOS' AS os_group

    UNION ALL

    SELECT 'Windows' AS os_group

    UNION ALL

    SELECT 'Linux' AS os_group

    UNION ALL

    SELECT 'Android' AS os_group

    UNION ALL

    SELECT 'Chrome OS' AS os_group

    UNION ALL

    SELECT 'Other' AS os_group

    UNION ALL

    SELECT 'Unknown' AS os_group

)

SELECT
    md5(os_group) AS os_group_id,
    os_group
FROM os_groups
