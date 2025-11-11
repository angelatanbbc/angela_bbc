{{ config(materialized="table") }}

SELECT
    {{ dbt_utils.generate_surrogate_key(['experience_id', 'template_id']) }} AS combination_id,
    experience_id,
    template_id,
    group_name_l1,
    group_name_l2
FROM  {{ ref('experience_template_combinations') }}
