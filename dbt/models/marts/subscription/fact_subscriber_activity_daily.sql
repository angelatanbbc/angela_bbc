{{
    config(
        materialized="table",
        tags=['fct', 'subscriptions']
    )
}}

WITH active_subscriber_days AS (

    SELECT
        date_day,
        user_first_party_id,
        COUNT(DISTINCT subscription_id) AS n_active_subscriptions,
        SUM(mrr_amount) AS mrr_amount
    FROM {{ ref('fact_subscriber_daily_snapshot') }}
    WHERE
        subscriber_status = 'Active'
        AND user_first_party_id IS NOT NULL
    GROUP BY date_day, user_first_party_id

),

subscriber_pageviews AS (

    SELECT
        event_time::DATE AS date_day,
        user_first_party_id,
        COUNT(DISTINCT visit_id) AS n_visits,
        COUNT(*) AS n_pageviews
    FROM {{ ref('stg_piano__studios_events') }}
    WHERE
        site_id IN (638824, 644938, 644937)
        AND event_time::DATE > '2025-06-25'
        AND event_name = 'page.display'
        AND user_first_party_id IS NOT NULL
    GROUP BY event_time::DATE, user_first_party_id

),

final AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key(['asd.date_day', 'asd.user_first_party_id']) }} AS subscriber_activity_daily_key,
        asd.date_day,
        asd.user_first_party_id,
        asd.n_active_subscriptions,
        asd.mrr_amount,
        COALESCE(sp.n_visits, 0) AS n_visits,
        COALESCE(sp.n_pageviews, 0) AS n_pageviews,
        COALESCE(sp.n_pageviews, 0) > 0 AS is_engaged
    FROM active_subscriber_days asd
    LEFT JOIN subscriber_pageviews sp
        ON asd.date_day = sp.date_day
        AND asd.user_first_party_id = sp.user_first_party_id

)

SELECT *
FROM final
ORDER BY user_first_party_id, date_day
