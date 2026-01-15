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
        app_type,
        os_group,
        experience_id,
        card_id,
        card_name,
        card_action,
        template_id,
        ab_test_variant_name
    FROM {{ ref('stg_piano__subs_events_app') }} e
    WHERE
        event_name IN ('experience.action', 'experience.interaction')
        {% if is_incremental() %}
        AND event_time >= DATEADD(DAY, -1, (SELECT MAX(exposure_time) FROM {{ this }}))
        {% endif %}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY exposure_id ORDER BY exposure_time DESC) = 1
    
),

app_experiences AS (

    SELECT *
    FROM {{ ref('app_experiences') }}
),

app_templates AS (

    SELECT *
    FROM {{ ref('app_templates') }}
),

named AS (
    
    SELECT
        f.*,
        e.experience_name,
        t.template_name
    FROM exposures f
    LEFT JOIN app_experiences e
        ON f.experience_id = e.experience_id
    LEFT JOIN app_templates t
        ON f.template_id = t.template_id

),

final AS (

    SELECT
        exposure_id,
        exposure_time,
        visit_id,
        visit_time,
        visitor_id,
        user_id,
        app_type,
        os_group,
        IFNULL(experience_id, 'EX0000000000') AS experience_id,
        IFNULL(experience_name, '000 - Unknown Experience') AS experience_name,
        card_id,
        card_name,
        card_action,
        IFNULL(template_id, 'OT0000000000') AS template_id,
        IFNULL(template_name, 'Unknown Template') AS template_name,
        ab_test_variant_name
    FROM named

)

SELECT *
FROM final
