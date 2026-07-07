{% macro ban_period_row(metric_label, metric_name, period_type, comparison_type, metric_format) %}
    SELECT
        '{{ metric_label }}' AS metric_label,
        '{{ metric_name }}' AS metric_name,
        '{{ period_type }}' AS period_type,
        {% if period_type == 'LATEST' %}
        as_of_date AS current_start_date,
        as_of_date AS current_end_date,
        DATEADD(MONTH, -1, as_of_date) AS prior_start_date,
        DATEADD(MONTH, -1, as_of_date) AS prior_end_date,
        {% elif period_type == 'WTD' %}
        DATE_TRUNC('week', as_of_date)::DATE AS current_start_date,
        as_of_date AS current_end_date,
        DATEADD(WEEK, -1, DATE_TRUNC('week', as_of_date)::DATE) AS prior_start_date,
        DATEADD(WEEK, -1, as_of_date) AS prior_end_date,
        {% elif period_type == 'MTD' %}
        DATE_TRUNC('month', as_of_date)::DATE AS current_start_date,
        as_of_date AS current_end_date,
        DATEADD(MONTH, -1, DATE_TRUNC('month', as_of_date)::DATE) AS prior_start_date,
        LEAST(
            DATEADD(
                DAY,
                DATEDIFF(DAY, DATE_TRUNC('month', as_of_date)::DATE, as_of_date),
                DATEADD(MONTH, -1, DATE_TRUNC('month', as_of_date)::DATE)
            ),
            LAST_DAY(DATEADD(MONTH, -1, DATE_TRUNC('month', as_of_date)::DATE))
        ) AS prior_end_date,
        {% elif period_type == 'L7D' %}
        DATEADD(DAY, -6, as_of_date) AS current_start_date,
        as_of_date AS current_end_date,
        DATEADD(DAY, -13, as_of_date) AS prior_start_date,
        DATEADD(DAY, -7, as_of_date) AS prior_end_date,
        {% elif period_type == 'L30D' %}
        DATEADD(DAY, -29, as_of_date) AS current_start_date,
        as_of_date AS current_end_date,
        DATEADD(DAY, -59, as_of_date) AS prior_start_date,
        DATEADD(DAY, -30, as_of_date) AS prior_end_date,
        {% else %}
        {{ exceptions.raise_compiler_error("Unsupported BAN period_type: " ~ period_type) }}
        {% endif %}
        '{{ comparison_type }}' AS comparison_type,
        '{{ metric_format }}' AS metric_format
    FROM as_of
{% endmacro %}
