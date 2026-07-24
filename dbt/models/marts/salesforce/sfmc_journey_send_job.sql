{{ config(
        materialized="table",
        tags=['salesforce', 'sfmc', 'mart']
    )
}}

WITH full_data AS (
    SELECT e.SendID,
           j1.email_name AS EmailName,
           j1.subject AS EmailSubject,
           e.EventDate,
           YEAR(e.EventDate) AS Year,
           j1.ListID,
           j1.ListName,
           e.Sent,
           COALESCE(e.Sent,0) - COALESCE(e.UniqueBounces,0) AS Delivered,
           e.UniqueOpens,
           e.TotalOpens,
           e.UniqueClicks,
           e.TotalClicks,
           e.UniqueBounces,
           e.TotalBounces,
           coalesce(e.UniqueUnsubscribes,0) AS Unsubscribes,
           CASE WHEN COALESCE(e.Sent, 0) > 0 THEN 
                CAST(COALESCE(e.UniqueOpens, 0) * 1.0 / COALESCE(e.Sent, 0) AS DECIMAL(10, 4))
           END AS OpenRate,
           CASE WHEN COALESCE(e.Sent, 0) > 0 THEN 
                CAST(COALESCE(e.UniqueClicks, 0) * 1.0 / COALESCE(e.Sent, 0) AS DECIMAL(10, 4))
           END AS ClickRate,
           CASE WHEN COALESCE(e.UniqueOpens, 0) > 0 THEN 
                CAST(COALESCE(e.UniqueClicks, 0) * 1.0 / COALESCE(e.UniqueOpens, 0) AS DECIMAL(10, 4))
           END AS ClickToOpen,
           CASE WHEN COALESCE(e.Sent, 0) > 0 THEN 
                CAST(COALESCE(e.UniqueBounces, 0) * 1.0 / COALESCE(e.Sent, 0) AS DECIMAL(10, 4))
           END AS BounceRate,
           CASE WHEN COALESCE(e.Sent, 0) > 0 THEN 
                CAST(COALESCE(e.UniqueUnsubscribes, 0) * 1.0 / COALESCE(e.Sent, 0) AS DECIMAL(10, 4))
           END AS UnsubscribeRate,
           j1.journey_name AS JourneyName,
           j1.activity_name AS ActivityName
    FROM (
        -- Aggregate e subquery
        SELECT s.send_id AS SendID,
               MIN(s.EventDate) AS EventDate,
               SUM(s.Sent) AS Sent,
               SUM(o.TotalOpens) AS TotalOpens,
               SUM(o.UniqueOpens) AS UniqueOpens,
               SUM(c.TotalClicks) AS TotalClicks,
               SUM(c.UniqueClicks) AS UniqueClicks,
               SUM(b.TotalBounces) AS TotalBounces,
               SUM(b.UniqueBounces) AS UniqueBounces,
               SUM(u.TotalUnsubscribes) AS TotalUnsubscribes,
               SUM(u.UniqueUnsubscribes) AS UniqueUnsubscribes
        FROM (
            SELECT send_id,
                   batch_id,
                   TO_DATE(event_date) AS EventDate,
                   COUNT(*) AS Sent
            FROM {{source('sfmc', 'sent')}}
            WHERE triggered_send_external_key IS NOT NULL
            GROUP BY send_id, batch_id, TO_DATE(event_date)
        ) s
        LEFT JOIN (
            SELECT send_id,
                   batch_id,
                   COUNT(*) AS TotalOpens,
                   SUM(CASE WHEN is_unique = 1 THEN 1 ELSE 0 END) AS UniqueOpens
            FROM {{source('sfmc', 'opens')}}
            WHERE triggered_send_external_key IS NOT NULL
            GROUP BY send_id, batch_id
        ) o ON s.send_id = o.send_id AND s.batch_id = o.batch_id
        LEFT JOIN (
            SELECT send_id,
                   batch_id,
                   COUNT(*) AS TotalClicks,
                   SUM(CASE WHEN is_unique = 1 THEN 1 ELSE 0 END) AS UniqueClicks
            FROM {{source('sfmc', 'clicks')}}
            WHERE triggered_send_external_key IS NOT NULL
            GROUP BY send_id, batch_id
        ) c ON s.send_id = c.send_id AND s.batch_id = c.batch_id
        LEFT JOIN (
            SELECT send_id,
                   batch_id,
                   COUNT(*) AS TotalBounces,
                   TotalBounces AS UniqueBounces
            FROM {{source('sfmc', 'bounces')}}
            WHERE triggered_send_external_key IS NOT NULL
            GROUP BY send_id, batch_id
        ) b ON s.send_id = b.send_id AND s.batch_id = b.batch_id
        LEFT JOIN (
            SELECT send_id,
                   batch_id,
                   COUNT(*) AS TotalUnsubscribes,
                   TotalUnsubscribes AS UniqueUnsubscribes
            FROM {{source('sfmc', 'unsubs')}}
            GROUP BY send_id, batch_id
        ) u ON s.send_id = u.send_id AND s.batch_id = u.batch_id
        GROUP BY s.send_id, s.EventDate
    ) e
    JOIN (
        -- Aggregate j1 subquery
        SELECT j.send_id,
               j.email_name,
               j.subject,
               COALESCE(l.list_id, 1) AS ListID,
               CASE 
                   WHEN j.send_definition_external_key = 'NewsBriefing_Weekend_AMERICAS' THEN 'News Briefing RSS'
                   WHEN l.list_name = 'News Briefing' AND DATE_PART(HOUR,j.sent_time) >= 12 THEN 'News Briefing PM'
                   WHEN l.list_name = 'The Essential List' AND UPPER(TO_CHAR(j.sent_time, 'DY')) = 'TUE' THEN 'The Essential List Tuesday'
                   ELSE COALESCE(l.list_name, 'NULL') 
               END AS ListName,
               jc.journey_name,
               jc.activity_name
        FROM {{source('sfmc', 'send_jobs')}} j
        LEFT JOIN (
            SELECT activity_name,
                   journey_name,
                   TO_CHAR(triggered_send_customer_key) AS triggered_send_customer_key
            FROM {{source('sfmc', 'journey_activity')}} ja
            LEFT JOIN {{source('sfmc', 'journey')}} jj ON ja.version_id = jj.version_id
        ) jc ON j.triggered_send_external_key = jc.triggered_send_customer_key
        LEFT JOIN (
            SELECT l0.send_id,
                   l0.list_id,
                   CASE 
                       WHEN l0.send_id = 3967798 THEN '3967798'
                       WHEN l0.send_id = 4027064 THEN '4027064'
                       WHEN l0.send_id IN (3991279, 3996996) THEN 'News Briefing'
                       ELSE REPLACE(l1.List_Name, 'News Briefing DEV', 'News Briefing')
                   END AS List_Name
            FROM (
                SELECT DISTINCT send_id, list_id
                FROM {{source('sfmc', 'sent')}}
                WHERE triggered_send_external_key IS NOT NULL
            ) l0
            JOIN (
                SELECT DISTINCT list_id, list_name
                FROM {{source('sfmc', 'list_subscribers')}}
                WHERE list_name IS NOT NULL
                GROUP BY list_id, list_name
            ) l1 ON l0.list_id = l1.list_id
        ) l ON j.send_id = l.send_id
        WHERE jc.journey_name IS NOT NULL
          AND l.list_name IS NOT NULL
          AND j.email_name NOT LIKE '%Welcome%'
          AND l.list_name != 'FM_Test'
    ) j1 ON e.SendID = j1.send_id
)
SELECT *
FROM full_data
QUALIFY ROW_NUMBER() OVER (PARTITION BY EmailName, EmailSubject, EventDate ORDER BY EventDate) = 1
ORDER BY EventDate, EmailName
