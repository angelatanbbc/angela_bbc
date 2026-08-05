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

acquisition_period_windows AS (

    {{ ban_period_row(
        metric_label='Organic Sign-ups',
        metric_name='organic_signups',
        period_type='MTD',
        comparison_type='Prior MTD',
        metric_format='number'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Paid Sign-ups',
        metric_name='paid_signups',
        period_type='MTD',
        comparison_type='Prior MTD',
        metric_format='number'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='% Annual Plans',
        metric_name='pct_annual',
        period_type='MTD',
        comparison_type='Prior Month',
        metric_format='percentage'
    ) }}

    UNION ALL

    {{ ban_period_row(
        metric_label='Funnel Conversion Rate',
        metric_name='funnel_conv_rate',
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
        metric_label='Subscription ARPU',
        metric_name='subscription_arpu',
        period_type='MTD',
        comparison_type='Prior MTD',
        metric_format='currency'
    ) }}

),

subscriber_activity AS (

    SELECT
        date_day,
        user_first_party_id,
        is_engaged,
        n_visits,
        n_pageviews
    FROM {{ ref('fact_subscriber_activity_daily') }}

),

subscription_events AS (

    SELECT
        event_time::DATE AS event_date,
        subscription_action,
        mrr_change_amount,
        transaction_value
    FROM {{ ref('fact_subscription_events') }}

),

site_visitors AS (

    SELECT
        date_key AS activity_date,
        visitor_id
    FROM {{ ref('fact_visitors_daily') }}

),

conversions AS (

    SELECT
        conversion_date,
        conversion_id,
        attribution_source,
        COALESCE(billing_period, 'Unknown') AS billing_period,
        position_weight
    FROM {{ ref('fact_conversions') }}

),

exposed_visitors AS (

    SELECT
        exposure_date,
        visitor_id
    FROM {{ ref('fact_exposures') }}

),

active_subscribers AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        COUNT(DISTINCT IFF(sa.date_day = pw.current_end_date, sa.user_first_party_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(sa.date_day = pw.prior_end_date, sa.user_first_party_id, NULL)) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscriber_activity sa
        ON sa.date_day IN (pw.current_end_date, pw.prior_end_date)
    WHERE pw.metric_name = 'active_subscribers'
    GROUP BY pw.metric_name, pw.period_type

),

active_subscribers_by_period AS (

    SELECT
        pw.period_type,
        COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date, sa.user_first_party_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date, sa.user_first_party_id, NULL)) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscriber_activity sa
        ON sa.date_day BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'active_subscribers_by_period'
    GROUP BY pw.period_type

),

engaged_subscribers AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date AND sa.is_engaged, sa.user_first_party_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date AND sa.is_engaged, sa.user_first_party_id, NULL)) AS prior_value
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
            / NULLIF(COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.current_start_date AND pw.current_end_date, sa.user_first_party_id, NULL)), 0) AS current_value,
        SUM(IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date, sa.n_visits, 0))
            / NULLIF(COUNT(DISTINCT IFF(sa.date_day BETWEEN pw.prior_start_date AND pw.prior_end_date, sa.user_first_party_id, NULL)), 0) AS prior_value
    FROM period_windows pw
    LEFT JOIN subscriber_activity sa
        ON sa.date_day BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'avg_subscriber_visits_per_period'
    GROUP BY pw.metric_name, pw.period_type

),

-- Sign-up counts use fractional multi-touch attribution: position_weight sums to 1
-- per conversion_id, so organic + paid equals the exact distinct conversion count.
organic_signups AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        COALESCE(SUM(IFF(c.conversion_date BETWEEN pw.current_start_date AND pw.current_end_date AND c.attribution_source = 'Organic', c.position_weight, 0)), 0) AS current_value,
        COALESCE(SUM(IFF(c.conversion_date BETWEEN pw.prior_start_date AND pw.prior_end_date AND c.attribution_source = 'Organic', c.position_weight, 0)), 0) AS prior_value
    FROM acquisition_period_windows pw
    LEFT JOIN conversions c
        ON c.conversion_date BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'organic_signups'
    GROUP BY pw.metric_name, pw.period_type

),

paid_signups AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        COALESCE(SUM(IFF(c.conversion_date BETWEEN pw.current_start_date AND pw.current_end_date AND c.attribution_source = 'Paid', c.position_weight, 0)), 0) AS current_value,
        COALESCE(SUM(IFF(c.conversion_date BETWEEN pw.prior_start_date AND pw.prior_end_date AND c.attribution_source = 'Paid', c.position_weight, 0)), 0) AS prior_value
    FROM acquisition_period_windows pw
    LEFT JOIN conversions c
        ON c.conversion_date BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'paid_signups'
    GROUP BY pw.metric_name, pw.period_type

),

pct_annual AS (

    SELECT
        pw.metric_name,
        pw.period_type,
        COUNT(DISTINCT IFF(c.conversion_date BETWEEN pw.current_start_date AND pw.current_end_date AND c.billing_period = '1 year', c.conversion_id, NULL))
            / NULLIF(COUNT(DISTINCT IFF(c.conversion_date BETWEEN pw.current_start_date AND pw.current_end_date, c.conversion_id, NULL)), 0) AS current_value,
        COUNT(DISTINCT IFF(c.conversion_date BETWEEN pw.prior_start_date AND pw.prior_end_date AND c.billing_period = '1 year', c.conversion_id, NULL))
            / NULLIF(COUNT(DISTINCT IFF(c.conversion_date BETWEEN pw.prior_start_date AND pw.prior_end_date, c.conversion_id, NULL)), 0) AS prior_value
    FROM acquisition_period_windows pw
    LEFT JOIN conversions c
        ON c.conversion_date BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'pct_annual'
    GROUP BY pw.metric_name, pw.period_type

),

-- All-time totals for the acquisition BANs whose big number is the full history
-- (the MTD current/prior values only drive the period-over-period change).
conversion_lifetime_totals AS (

    SELECT
        SUM(IFF(attribution_source = 'Organic', position_weight, 0)) AS organic_signups_lifetime,
        SUM(IFF(attribution_source = 'Paid', position_weight, 0)) AS paid_signups_lifetime,
        COUNT(DISTINCT IFF(billing_period = '1 year', conversion_id, NULL))
            / NULLIF(COUNT(DISTINCT conversion_id), 0) AS pct_annual_lifetime
    FROM conversions

),

funnel_mtd_conversions AS (

    SELECT
        pw.period_type,
        COUNT(DISTINCT IFF(c.conversion_date BETWEEN pw.current_start_date AND pw.current_end_date, c.conversion_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(c.conversion_date BETWEEN pw.prior_start_date AND pw.prior_end_date, c.conversion_id, NULL)) AS prior_value
    FROM acquisition_period_windows pw
    LEFT JOIN conversions c
        ON c.conversion_date BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'funnel_conv_rate'
    GROUP BY pw.period_type

),

funnel_mtd_exposed AS (

    SELECT
        pw.period_type,
        COUNT(DISTINCT IFF(ev.exposure_date BETWEEN pw.current_start_date AND pw.current_end_date, ev.visitor_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(ev.exposure_date BETWEEN pw.prior_start_date AND pw.prior_end_date, ev.visitor_id, NULL)) AS prior_value
    FROM acquisition_period_windows pw
    LEFT JOIN exposed_visitors ev
        ON ev.exposure_date BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'funnel_conv_rate'
    GROUP BY pw.period_type

),

funnel_conv_rate AS (

    SELECT
        'funnel_conv_rate' AS metric_name,
        fc.period_type,
        fc.current_value / NULLIF(fe.current_value, 0) AS current_value,
        fc.prior_value / NULLIF(fe.prior_value, 0) AS prior_value
    FROM funnel_mtd_conversions fc
    JOIN funnel_mtd_exposed fe
        ON fc.period_type = fe.period_type

),

arpu_transaction_value AS (

    SELECT
        pw.period_type,
        COALESCE(SUM(IFF(se.event_date BETWEEN pw.current_start_date AND pw.current_end_date, se.transaction_value, 0)), 0) AS current_value,
        COALESCE(SUM(IFF(se.event_date BETWEEN pw.prior_start_date AND pw.prior_end_date, se.transaction_value, 0)), 0) AS prior_value
    FROM acquisition_period_windows pw
    LEFT JOIN subscription_events se
        ON se.event_date BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE
        pw.metric_name = 'subscription_arpu'
        AND se.subscription_action = 'New subscription'
    GROUP BY pw.period_type

),

arpu_site_visitors AS (

    SELECT
        pw.period_type,
        COUNT(DISTINCT IFF(sv.activity_date BETWEEN pw.current_start_date AND pw.current_end_date, sv.visitor_id, NULL)) AS current_value,
        COUNT(DISTINCT IFF(sv.activity_date BETWEEN pw.prior_start_date AND pw.prior_end_date, sv.visitor_id, NULL)) AS prior_value
    FROM acquisition_period_windows pw
    LEFT JOIN site_visitors sv
        ON sv.activity_date BETWEEN pw.prior_start_date AND pw.current_end_date
    WHERE pw.metric_name = 'subscription_arpu'
    GROUP BY pw.period_type

),

-- Stored as revenue per 1,000 distinct site visitors (the raw per-visitor ratio is
-- fractions of a penny); pct_change is unaffected by the scaling.
subscription_arpu AS (

    SELECT
        'subscription_arpu' AS metric_name,
        tv.period_type,
        1000 * tv.current_value / NULLIF(sv.current_value, 0) AS current_value,
        1000 * tv.prior_value / NULLIF(sv.prior_value, 0) AS prior_value
    FROM arpu_transaction_value tv
    JOIN arpu_site_visitors sv
        ON tv.period_type = sv.period_type

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

acquisition_unioned AS (

    SELECT *
    FROM organic_signups

    UNION ALL

    SELECT *
    FROM paid_signups

    UNION ALL

    SELECT *
    FROM pct_annual

    UNION ALL

    SELECT *
    FROM funnel_conv_rate

    UNION ALL

    -- The acquisition dashboard reuses the subscriber MRR movement metric; the MTD
    -- window is identical because both dashboards share the same as_of date.
    SELECT *
    FROM mrr_change

    UNION ALL

    SELECT *
    FROM subscription_arpu

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
        NULL::NUMBER(38, 6) AS lifetime_value,
        pw.metric_format,
        TRUE AS is_higher_better
    FROM period_windows pw
    CROSS JOIN as_of a
    JOIN unioned u
        ON pw.metric_name = u.metric_name
        AND pw.period_type = u.period_type

),

acquisition_final AS (

    SELECT
        {{ ban_surrogate_key(
            dashboard_name="'acquisition'",
            metric_name='pw.metric_name',
            period_type='pw.period_type',
            as_of_date='a.as_of_date'
        ) }} AS subscriber_ban_key,
        a.as_of_date,
        'acquisition' AS dashboard_name,
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
        CASE pw.metric_name
            WHEN 'organic_signups' THEN lt.organic_signups_lifetime
            WHEN 'paid_signups' THEN lt.paid_signups_lifetime
            WHEN 'pct_annual' THEN lt.pct_annual_lifetime
        END::NUMBER(38, 6) AS lifetime_value,
        pw.metric_format,
        TRUE AS is_higher_better
    FROM acquisition_period_windows pw
    CROSS JOIN as_of a
    CROSS JOIN conversion_lifetime_totals lt
    JOIN acquisition_unioned u
        ON pw.metric_name = u.metric_name
        AND pw.period_type = u.period_type

)

SELECT *
FROM final

UNION ALL

SELECT *
FROM acquisition_final
