{{ config(materialized="table") }}

WITH web_exposures AS (

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
        experience_name,
        card_id,
        card_name,
        card_action,
        template_id,
        template_name,
        ab_test_variant_name,
        bbc_team,
        is_paid_exposure
    FROM {{ ref('int_piano__exposures_web') }}

),

app_exposures AS (

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
        experience_name,
        card_id,
        card_name,
        card_action,
        template_id,
        template_name,
        ab_test_variant_name,
        NULL AS bbc_team,
        FALSE AS is_paid_exposure
    FROM {{ ref('int_piano__exposures_app') }}

)

SELECT * FROM web_exposures

UNION ALL

SELECT * FROM app_exposures
