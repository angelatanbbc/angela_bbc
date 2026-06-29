{{ config(materialized="table") }}

WITH web_exposures AS (

    SELECT *
    FROM {{ ref('int_piano__exposures_web') }}

),

app_exposures AS (

    SELECT *
    FROM {{ ref('int_piano__exposures_app') }}

)

SELECT
    exposure_id,
    experience_execution_id,
    exposure_time,
    exposure_date,
    pageview_id,
    visitor_id,
    visit_id,
    user_id,
    app_type_id,
    device_type_id,
    os_group_id,
    page,
    page_title,
    page_content_type,
    content_type,
    content_id,
    content_section,
    content_topic,
    content_pillar,
    date_published,
    url,
    geo_id,
    geo_country,
    geo_region,
    geo_city,
    experience_id,
    experience_name,
    card_id,
    card_name,
    card_action,
    template_id,
    template_name,
    ab_test_card_title,
    ab_test_variant_name,
    c1x_lts,
    c1x_content_likely_to_convert,
    c1x_likelihood_to_register,
    c1x_likelihood_to_return,
    c1x_revenue_auto_optimization
FROM web_exposures

UNION ALL

SELECT
    exposure_id,
    experience_execution_id,
    exposure_time,
    exposure_date,
    pageview_id,
    visitor_id,
    visit_id,
    user_id,
    app_type_id,
    device_type_id,
    os_group_id,
    page,
    page_title,
    page_content_type,
    content_type,
    content_id,
    content_section,
    content_topic,
    content_pillar,
    date_published,
    url,
    geo_id,
    geo_country,
    geo_region,
    geo_city,
    experience_id,
    experience_name,
    card_id,
    card_name,
    card_action,
    template_id,
    template_name,
    ab_test_card_title,
    ab_test_variant_name,
    c1x_lts,
    c1x_content_likely_to_convert,
    c1x_likelihood_to_register,
    c1x_likelihood_to_return,
    c1x_revenue_auto_optimization
FROM app_exposures
