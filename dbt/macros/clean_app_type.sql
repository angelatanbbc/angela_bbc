{% macro clean_app_type(column_name='app_type') %}
    CASE
        WHEN {{ column_name }} IS NULL THEN 'Unknown'
        WHEN LOWER({{ column_name }}) = 'responsive' THEN 'Web'
        WHEN LOWER({{ column_name }}) = 'mobile-app' THEN 'Mobile App'
        ELSE {{ column_name }}
    END
{% endmacro %}
