{{
    config(
        materialized="incremental",
        unique_key="exposure_id",
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

WITH exposures AS (
    
    SELECT
        -- Dims
        {{ dbt_utils.generate_surrogate_key(
            ['event_time', 'experience_id', 'card_id', 'template_id', 'ab_test_variant_name']
        ) }} AS exposure_id,
        event_time AS exposure_time,
        visit_id,
        visit_time,
        visitor_id,
        user_id,
        device_type,
        app_type,
        os_group,
        experience_id,
        experience_name,
        card_id,
        card_name,
        card_action,
        template_id,
        template_name,
        ab_test_variant_name
    FROM {{ ref('stg_piano__subs_events_web') }} e
    WHERE
        event_name IN ('experience.action', 'experience.interaction')
        AND experience_id != 'EXFXDKMDXAX0' -- Policy Modal
        AND template_name != 'Outside Region Error Message'
        {% if is_incremental() %}
        AND event_time >= DATEADD(DAY, -1, (SELECT MAX(exposure_time) FROM {{ this }}))
        {% endif %}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY exposure_id ORDER BY exposure_time DESC) = 1
    
),

final AS (

    SELECT
        exposure_id,
        exposure_time,
        visit_id,
        visit_time,
        visitor_id,
        user_id,
        device_type,
        app_type,
        os_group,
        experience_id,
        -- Fill forward experience_name to handle cases where it is NULL
        LAST_VALUE(experience_name) IGNORE NULLS OVER (
            PARTITION BY experience_id
            ORDER BY exposure_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS experience_name,
        card_id,
        card_name,
        card_action,
        template_id,
        template_name,
        ab_test_variant_name
    FROM exposures

)

SELECT *
FROM final
