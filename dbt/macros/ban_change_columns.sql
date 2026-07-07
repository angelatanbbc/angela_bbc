{% macro ban_change_columns(current_value, prior_value) %}
    ({{ current_value }} - {{ prior_value }})::NUMBER(38, 6) AS absolute_change,
    (({{ current_value }} - {{ prior_value }}) / NULLIF({{ prior_value }}, 0))::NUMBER(38, 6) AS pct_change
{% endmacro %}
