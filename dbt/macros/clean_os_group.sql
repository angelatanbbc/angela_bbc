{% macro clean_os_group(column_name='os_group') %}
    CASE
        WHEN {{ column_name }} IS NULL THEN 'Unknown'
        WHEN LOWER({{ column_name }}) NOT IN ('ios', 'android', 'windows', 'macos', 'ipados', 'chrome os', 'linux') THEN 'Other'
        ELSE {{ column_name }}
    END
{% endmacro %}
