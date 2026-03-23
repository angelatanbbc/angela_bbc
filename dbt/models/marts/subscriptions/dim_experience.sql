{{ config(materialized="table") }}

WITH exposures AS (

    SELECT *
    FROM {{ ref('fact_exposures') }}
    WHERE
        experience_id IS NOT NULL
        AND experience_name IS NOT NULL
        AND experience_id != 'EXFXDKMDXAX0'  -- Filter policy modal

),

latest_experience_name AS (

    SELECT
        experience_id,
        experience_name,
        MAX(exposure_time) AS latest_exposure_time,
        ROW_NUMBER() OVER (
            PARTITION BY experience_id
            ORDER BY latest_exposure_time DESC
        ) AS rn
    FROM exposures
    GROUP BY 1,2

)

SELECT
    experience_id,
    experience_name
FROM latest_experience_name
WHERE rn = 1
ORDER BY experience_name
