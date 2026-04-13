{% macro clean_os_group(column_name='os_group') %}
    CASE
        WHEN {{ column_name }} IS NULL THEN 'Unknown'
        WHEN LOWER({{ column_name }}) IN ('ios', 'ipados') THEN 'iOS'
        WHEN LOWER({{ column_name }}) = 'macos' THEN 'macOS'
        WHEN LOWER({{ column_name }}) = 'windows' THEN 'Windows'
        WHEN LOWER({{ column_name }}) = 'chrome os' THEN 'Chrome OS'
        WHEN LOWER({{ column_name }}) = 'linux' THEN 'Linux'
        WHEN LOWER({{ column_name }}) = 'android' THEN 'Android'
        ELSE 'Other'
    END
{% endmacro %}
