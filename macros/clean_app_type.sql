{#
    Normalised app type label from Piano's app_type. Idempotent: accepts the raw
    Piano value or an already-cleaned label, so callers can pass a literal
    ('Web') as well as a column.
#}
{% macro clean_app_type(expr) %}
    CASE
        WHEN LOWER(TRIM({{ expr }})) IN ('web', 'responsive', 'mobile-responsive') THEN 'Web'
        WHEN LOWER(TRIM({{ expr }})) IN ('mobile app', 'mobile-app') THEN 'Mobile App'
        WHEN NULLIF(LOWER(TRIM({{ expr }})), '') IS NULL OR LOWER(TRIM({{ expr }})) = 'unknown' THEN 'Unknown'
        ELSE 'Other'
    END
{% endmacro %}
