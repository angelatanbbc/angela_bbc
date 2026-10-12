{% macro generate_os_group_id(column_name='os_group') %}
    CASE
        WHEN {{ column_name }} IS NULL THEN MD5('Unknown')
        WHEN LOWER({{ column_name }}) IN ('ios', 'ipados') THEN MD5('iOS')
        WHEN LOWER({{ column_name }}) = 'macos' THEN MD5('macOS')
        WHEN LOWER({{ column_name }}) = 'windows' THEN MD5('Windows')
        WHEN LOWER({{ column_name }}) = 'chrome os' THEN MD5('Chrome OS')
        WHEN LOWER({{ column_name }}) = 'linux' THEN MD5('Linux')
        WHEN LOWER({{ column_name }}) = 'android' THEN MD5('Android')
        ELSE MD5('Other')
    END
{% endmacro %}
