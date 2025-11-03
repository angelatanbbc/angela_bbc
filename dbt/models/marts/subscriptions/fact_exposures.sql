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
        {{ dbt_utils.generate_surrogate_key(['visit_id', 'experience_id', 'template_id', 'ab_test_variant_name']) }} AS exposure_id,
        visit_id,
        visit_time,
        visitor_id,
        user_id,
        experience_id,
        template_id,
        ab_test_variant_name,
        
        -- Time
        MIN(event_time) AS first_shown_time,
        MAX(event_time) AS last_shown_time,

        -- Measures
        COUNT_IF(event_name = 'experience.action') AS count_exposures,
        COUNT_IF(event_name = 'experience.interaction') AS count_interactions

    FROM {{ ref('stg_piano_events__exposures') }}
    WHERE
        event_name IN ('experience.action', 'experience.interaction')
        AND template_name != 'Outside Region Error Message'
        {% if is_incremental() %}
        AND visit_time >= DATEADD(DAY, -1, (SELECT MAX(visit_time) FROM {{ this }}))
        {% endif %}
    GROUP BY ALL
    
)

SELECT *
FROM exposures