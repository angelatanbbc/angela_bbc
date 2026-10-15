{#
    Normalised operating system group label from Piano's os_group, which arrives
    in mixed case (ios / iOS, ipados / iPadOS). Idempotent: accepts the raw
    Piano value or an already-cleaned label. iPadOS is its own group.
#}
{% macro clean_os_group(expr) %}
    CASE
        WHEN LOWER(TRIM({{ expr }})) = 'ios' THEN 'iOS'
        WHEN LOWER(TRIM({{ expr }})) = 'ipados' THEN 'iPadOS'
        WHEN LOWER(TRIM({{ expr }})) = 'macos' THEN 'macOS'
        WHEN LOWER(TRIM({{ expr }})) = 'windows' THEN 'Windows'
        WHEN LOWER(TRIM({{ expr }})) = 'linux' THEN 'Linux'
        WHEN LOWER(TRIM({{ expr }})) = 'android' THEN 'Android'
        WHEN LOWER(TRIM({{ expr }})) = 'chrome os' THEN 'Chrome OS'
        WHEN NULLIF(LOWER(TRIM({{ expr }})), '') IS NULL OR LOWER(TRIM({{ expr }})) = 'unknown' THEN 'Unknown'
        ELSE 'Other'
    END
{% endmacro %}
