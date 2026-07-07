{{ config(
    materialized='table',
    tags=['subscriptions', 'piano', 'tableau'],
) }}

WITH as_of AS (

    SELECT MAX(date_day) AS as_of_date
    FROM {{ ref('fact_subscriber_activity_daily') }}

),

period_windows AS (

    {{ ban_period_row(
        metric_label='Active Subscribers',
        metric_name='active_subscribers',
        period_type='LATEST',
        comparison_type='MoM',
        metric_format='number'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Engaged Subscribers',
        metric_name='engaged_subscribers',
        period_type='WTD',
        comparison_type='Prior WTD',
        metric_format='number'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Engaged Subscribers',
        metric_name='engaged_subscribers',
        period_type='MTD',
        comparison_type='Prior MTD',
        metric_format='number'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Engaged Subscribers %',
        metric_name='engaged_subscribers_pct',
        period_type='WTD',
        comparison_type='Prior WTD',
        metric_format='percentage'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Engaged Subscribers %',
        metric_name='engaged_subscribers_pct',
        period_type='MTD',
        comparison_type='Prior MTD',
        metric_format='percentage'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='MRR Change',
        metric_name='mrr_change',
        period_type='MTD',
        comparison_type='Prior MTD',
        metric_format='currency'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Average Subscriber Pageviews per Visit',
        metric_name='avg_subscriber_pageviews_per_visit',
        period_type='WTD',
        comparison_type='Prior WTD',
        metric_format='number'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Average Subscriber Pageviews per Visit',
        metric_name='avg_subscriber_pageviews_per_visit',
        period_type='MTD',
        comparison_type='Prior MTD',
        metric_format='number'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Average Subscriber Visits',
        metric_name='avg_subscriber_visits_per_period',
        period_type='L7D',
        comparison_type='Prior L7D',
        metric_format='number'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Average Subscriber Visits',
        metric_name='avg_subscriber_visits_per_period',
        period_type='L30D',
        comparison_type='Prior L30D',
        metric_format='number'
    ) }}

),

subscriber_activity AS (

    SELECT
        date_day,
        user_id,
        is_engaged,
        n_visits,
        n_pageviews
    FROM {{ ref('fact_subscriber_activity_daily') }}

),

subscription_events AS (

    SELECT
        event_time::DATE AS event_date,
        mrr_change_amount
    FROM {{ ref('fact_subscription_events') }}

),

active_subscribers AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        COUNT(DISTINCT IFF(sa.date_day = pw.current_end_date, sa.user_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(sa.date_day = pw.prior_end_date, sa.user_id, NULL)) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscriber_activity sa
        ON sa.date_day IN (pw.current_end_date, pw.prior_end_date)
    WHERE pw.metric_name = 'active_subscribers'
    GROUP BY pw.metric_name, pw.period_type

),

active_subscribers_by_period AS (

    SELECT
        pw.period_type,
        COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date, sa.user_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date, sa.user_id, NULL)) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscriber_activity sa
        ON sa.date_day BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'engaged_subscribers_pct'
    GROUP BY pw.period_type

),

engaged_subscribers AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date AND sa.is_engaged, sa.user_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date AND sa.is_engaged, sa.user_id, NULL)) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscriber_activity sa
        ON sa.date_day BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'engaged_subscribers'
    GROUP BY pw.metric_name, pw.period_type

),

engaged_subscribers_pct AS (

    SELECT
        'engaged_subscribers_pct' AS metric_name,
        es.period_type,
        es.current_value / NULLIF(asp.current_value, 0) AS current_value,
        es.prior_value / NULLIF(asp.prior_value, 0) AS prior_value
    FROM engaged_subscribers es
    JOIN active_subscribers_by_period asp
        ON es.period_type = asp.period_type

),

mrr_change AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        COALESCE(SUM(IFF(se.event_date BETWEEN pw.current_start_date AND pw.current_end_date, se.mrr_change_amount, 0)), 0) AS current_value,
        COALESCE(SUM(IFF(se.event_date BETWEEN pw.prior_start_date AND pw.prior_end_date, se.mrr_change_amount, 0)), 0) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscription_events se
        ON se.event_date BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'mrr_change'
    GROUP BY pw.metric_name, pw.period_type

),

avg_subscriber_pageviews_per_visit AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        SUM(IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date, sa.n_pageviews, 0))
            / NULLIF(SUM(IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date, sa.n_visits, 0)), 0) AS current_value,
        SUM(IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date, sa.n_pageviews, 0))
            / NULLIF(SUM(IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date, sa.n_visits, 0)), 0) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscriber_activity sa
        ON sa.date_day BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'avg_subscriber_pageviews_per_visit'
    GROUP BY pw.metric_name, pw.period_type

),

avg_subscriber_visits_per_period AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        SUM(IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date, sa.n_visits, 0))
            / NULLIF(COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date, sa.user_id, NULL)), 0) AS current_value,
        SUM(IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date, sa.n_visits, 0))
            / NULLIF(COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date, sa.user_id, NULL)), 0) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscriber_activity sa
        ON sa.date_day BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'avg_subscriber_visits_per_period'
    GROUP BY pw.metric_name, pw.period_type

),

unioned AS (

    SELECT *
    FROM active_subscribers

    UNION ALL

    SELECT *
    FROM engaged_subscribers

    UNION ALL

    SELECT *
    FROM engaged_subscribers_pct

    UNION ALL

    SELECT *
    FROM mrr_change

    UNION ALL

    SELECT *
    FROM avg_subscriber_pageviews_per_visit

    UNION ALL

    SELECT *
    FROM avg_subscriber_visits_per_period

),

final AS (

    SELECT
        {{ ban_surrogate_key(
            dashboard_name="'subscriber_activity'",
            metric_name='pw.metric_name',
            period_type='pw.period_type',
            as_of_date='a.as_of_date'
        ) }} AS subscriber_ban_key,
        a.as_of_date,
        'subscriber_activity' AS dashboard_name,
        pw.metric_name,
        pw.metric_label,
        pw.period_type,
        pw.current_start_date,
        pw.current_end_date,
        pw.prior_start_date,
        pw.prior_end_date,
        pw.comparison_type,
        u.current_value::NUMBER(38, 6) AS current_value,
        u.prior_value::NUMBER(38, 6) AS prior_value,
        {{ ban_change_columns(
            current_value='u.current_value',
            prior_value='u.prior_value'
        ) }},
        pw.metric_format,
        TRUE AS is_higher_better
    FROM period_windows pw
    CROSS JOIN as_of a
    JOIN unioned u
        ON pw.metric_name = u.metric_name
        AND pw.period_type = u.period_type

)

SELECT *
FROM final
