{% macro clean_device_type(column_name='device_type') %}
    CASE
        WHEN {{ column_name }} IS NULL THEN 'Unknown'
        WHEN LOWER({{ column_name }}) NOT IN ('mobile phone', 'desktop', 'tablet') THEN 'Other'
        ELSE {{ column_name }}
    END
{% endmacro %}
