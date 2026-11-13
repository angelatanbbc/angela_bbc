{#
    Surrogate key of dim_device_platform: a hash of the cleaned app type, device
    type and OS group labels. dim_device_platform builds its key with the same
    macro from its label lists, so every key derived from an event resolves.
    Each argument is a SQL expression: a raw Piano column, an already-cleaned
    label column, or a literal such as "'Web'" when a pipeline forces the app type.
#}
{% macro generate_device_platform_id(app_type_expr, device_type_expr, os_group_expr) %}
    MD5(CONCAT_WS(
        '|',
        {{ clean_app_type(app_type_expr) }},
        {{ clean_device_type(device_type_expr) }},
        {{ clean_os_group(os_group_expr) }}
    ))
{% endmacro %}
