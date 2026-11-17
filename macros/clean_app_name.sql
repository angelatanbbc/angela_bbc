{#
    Normalised app name label from Piano's app_name. Idempotent: accepts the raw
    Piano value or an already-cleaned label, so callers can pass a literal
    ('Web') as well as a column.
#}
{% macro clean_app_name(expr) %}
    CASE
        WHEN LOWER(TRIM({{ expr }})) IN ('web', 'bbc_web', 'bbc-website', 'news-live', 'news-sfv') THEN 'Web'
        WHEN LOWER(TRIM({{ expr }})) IN ('sport web', 'sport-gnl-web', 'sport-sfv') THEN 'Sport Web'
        WHEN LOWER(TRIM({{ expr }})) IN ('international app', 'bbc_apple', 'bbc_android') THEN 'International App'
        WHEN LOWER(TRIM({{ expr }})) IN ('old news app', 'news-gnl-app') THEN 'Old News App'
        WHEN LOWER(TRIM({{ expr }})) IN ('uk news app', 'news-uk-chrysalis-ios', 'news-uk-chrysalis-android', 'news-uk-chrysalis-ios') THEN 'UK News App'
        WHEN LOWER(TRIM({{ expr }})) IN ('sport app', 'sport-gnl-ios', 'sport-gnl-android', 'sport-gnl-app', 'sport-gnl-kindle') THEN 'Sport App'
        WHEN LOWER(TRIM({{ expr }})) IN ('uk sport app', 'sport-uk-ios', 'sport-uk-android', 'sport-uk-app', 'sport-uk-kindle') THEN 'UK Sport App'
        WHEN NULLIF(LOWER(TRIM({{ expr }})), '') IS NULL OR LOWER(TRIM({{ expr }})) = 'unknown' THEN 'Unknown'
        ELSE 'Other'
    END
{% endmacro %}