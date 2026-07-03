{% macro ban_surrogate_key(dashboard_name, metric_name, period_type, as_of_date) %}
    {{ dbt_utils.generate_surrogate_key([
        dashboard_name,
        metric_name,
        period_type,
        as_of_date
    ]) }}
{% endmacro %}
