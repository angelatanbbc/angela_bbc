{#
    Normalised device type label from Piano's device_type. Idempotent: accepts
    the raw Piano value or an already-cleaned label. The long tail (TV, Set Top
    Box, VR Headset, ...) is Other.
#}
{% macro clean_device_type(expr) %}
    CASE
        WHEN LOWER(TRIM({{ expr }})) = 'mobile phone' THEN 'Mobile Phone'
        WHEN LOWER(TRIM({{ expr }})) = 'desktop' THEN 'Desktop'
        WHEN LOWER(TRIM({{ expr }})) = 'tablet' THEN 'Tablet'
        WHEN NULLIF(LOWER(TRIM({{ expr }})), '') IS NULL OR LOWER(TRIM({{ expr }})) = 'unknown' THEN 'Unknown'
        ELSE 'Other'
    END
{% endmacro %}
