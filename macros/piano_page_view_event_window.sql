{#
    Event-time window for the incremental page view models. Renders AND-predicates
    to append to a WHERE clause over Piano events.

    - dev: only the last 3 days of events, so the nightly dev rebuild stays cheap.
    - incremental runs: reprocess from the day before the latest date already
      loaded. Rows are merged on pageview_id, so a page view whose events straddle
      the window boundary keeps the aggregate from its most recent run.

    event_time_column: event timestamp column of the model's input
    watermark_column:  timestamp column of the model itself used as the high-water mark
#}
{% macro piano_page_view_event_window(event_time_column='event_time', watermark_column='last_event_time') %}
    {% if target.name == 'dev' %}
        AND {{ event_time_column }} >= DATEADD(DAY, -3, CURRENT_DATE)
    {% endif %}
    {% if is_incremental() %}
        AND {{ event_time_column }}::DATE >= (SELECT DATEADD(DAY, -1, MAX({{ watermark_column }})::DATE) FROM {{ this }})
    {% endif %}
{% endmacro %}
