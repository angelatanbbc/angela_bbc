{{
    config(
        materialized="semantic_view",
        tags=["attribution"]
    )
}}

TABLES(
    touchpoints AS {{ ref('fct_attribution_touchpoints') }}
        PRIMARY KEY (attribution_touchpoint_sk)
        WITH SYNONYMS = ('attribution', 'credited touchpoints', 'touchpoints')
        COMMENT = 'One row per web subscription x credited touchpoint in the 30 days before it (click-based attribution)',
    channels AS {{ ref('dim_channel') }}
        PRIMARY KEY (channel_sk)
        WITH SYNONYMS = ('sources', 'traffic sources', 'channels')
        COMMENT = 'Where a touch came from: attribution source, channel group, agency and partner',
    campaign_tags AS {{ ref('dim_campaign_tracking') }}
        PRIMARY KEY (campaign_tracking_sk)
        WITH SYNONYMS = ('campaign tags', 'utm tags', 'tracking codes')
        COMMENT = 'The campaign tags on the visit: campaign, ad set, creative, medium, keyword',
    ads AS {{ ref('dim_ad') }}
        PRIMARY KEY (ad_sk)
        WITH SYNONYMS = ('ads', 'creatives')
        COMMENT = 'Meta, Google and Microsoft ads with their ad set, campaign and agency',
    device_platforms AS {{ ref('dim_device_platform') }}
        PRIMARY KEY (device_platform_id)
        WITH SYNONYMS = ('devices', 'platforms')
        COMMENT = 'App type, device type and operating system group of the touch'
)

RELATIONSHIPS(
    touchpoints_to_channels AS touchpoints (channel_sk) REFERENCES channels (channel_sk),
    touchpoints_to_campaign_tags AS touchpoints (campaign_tracking_sk) REFERENCES campaign_tags (campaign_tracking_sk),
    touchpoints_to_ads AS touchpoints (ad_sk) REFERENCES ads (ad_sk),
    touchpoints_to_device_platforms AS touchpoints (device_platform_id) REFERENCES device_platforms (device_platform_id)
)

FACTS(
    touchpoints.conversion_id AS conversion_id
        COMMENT = 'Piano id of the subscription purchase; count distinct for subscriptions',
    touchpoints.position_weight AS position_weight
        COMMENT = 'Position-based credit of the touch; sums to 1 per subscription',
    touchpoints.paid_position_weight AS IFF(is_paid_touch, position_weight, 0)
        COMMENT = 'Position-based credit on paid (8MS / DBS) touches only',
    touchpoints.signup_touch_weight AS signup_touch_weight
        COMMENT = 'Credit under the 40 / 40 / 20 first / purchase / middle model',
    touchpoints.first_touch_weight AS first_touch_weight
        COMMENT = '1 on the first touch of the journey',
    touchpoints.last_touch_weight AS last_touch_weight
        COMMENT = '1 on the last touch before the purchase',
    touchpoints.paid_conversion_id AS IFF(is_paid_touch, conversion_id, NULL)
        COMMENT = 'conversion_id on paid touches only, for subscriptions with a paid touch'
)

DIMENSIONS(
    touchpoints.touchpoint_date AS touchpoint_date
        WITH SYNONYMS = ('click date', 'touch date', 'date')
        COMMENT = 'Date of the touch - the date the attribution dashboard reports by',
    touchpoints.conversion_date AS conversion_date
        WITH SYNONYMS = ('purchase date', 'subscription date', 'sign-up date')
        COMMENT = 'Date the subscription was bought',
    touchpoints.touchpoint_type AS touchpoint_type
        COMMENT = 'page_view or conversion (the purchase itself)',
    touchpoints.is_paid_touch AS is_paid_touch
        WITH SYNONYMS = ('paid', 'paid media')
        COMMENT = 'TRUE when the touch came from an 8MS or DBS ad',
    touchpoints.billing_period AS billing_period
        WITH SYNONYMS = ('plan length', 'billing cycle')
        COMMENT = 'Billing period of the subscription bought (e.g. 1 month, 1 year)',
    touchpoints.identity_link_type AS identity_link_type
        COMMENT = 'How the touch was tied to the buyer: checkout_cookie, account or device',
    touchpoints.country AS geo_country
        WITH SYNONYMS = ('market')
        COMMENT = 'Country of the touch',
    touchpoints.browser_group AS browser_group
        WITH SYNONYMS = ('browser')
        COMMENT = 'Browser group of the touch',
    touchpoints.content_pillar AS content_pillar
        WITH SYNONYMS = ('pillar')
        COMMENT = 'Content pillar of the page the touch happened on',
    channels.channel_group AS channel_group
        WITH SYNONYMS = ('channel', 'source group')
        COMMENT = 'Attribution source grouped as on the dashboard',
    channels.attribution_source AS attribution_source
        WITH SYNONYMS = ('source', 'traffic source')
        COMMENT = 'Source credited for the touch: Paid, Direct traffic, Search engines, a promo code ...',
    channels.attribution_source_detail AS attribution_source_detail
        WITH SYNONYMS = ('source detail')
        COMMENT = 'Detail of the credited source: the agency for paid touches, the referrer or engine otherwise',
    channels.agency AS agency
        WITH SYNONYMS = ('media agency', 'bbc team')
        COMMENT = 'Paid-media agency: 8ms or dbs',
    channels.partner AS partner
        WITH SYNONYMS = ('platform', 'publisher')
        COMMENT = 'Partner the visit came from: facebook, instagram, google ...',
    campaign_tags.campaign AS campaign
        WITH SYNONYMS = ('campaign name', 'src campaign')
        COMMENT = 'Campaign tag on the visit',
    campaign_tags.ad_set_name AS ad_set_name
        WITH SYNONYMS = ('ad set', 'adset')
        COMMENT = 'Ad set tag on the visit',
    campaign_tags.creative_id AS creative_id
        WITH SYNONYMS = ('ad id', 'creative')
        COMMENT = 'Creative (Meta ad) id tag on the visit',
    campaign_tags.medium AS medium
        COMMENT = 'Medium tag on the visit',
    campaign_tags.keyword AS keyword
        WITH SYNONYMS = ('search term')
        COMMENT = 'Paid-search keyword on the visit',
    ads.ad_platform AS platform
        WITH SYNONYMS = ('ad platform')
        COMMENT = 'Platform the ad ran on: meta, google or microsoft',
    ads.ad_name AS ad_name
        COMMENT = 'Name of the ad as its platform reports it',
    ads.platform_campaign_name AS campaign_name
        WITH SYNONYMS = ('platform campaign', 'meta campaign')
        COMMENT = 'Campaign name as the ad platform reports it (Meta only; the Google upload has no campaign)',
    device_platforms.device_platform AS platform
        WITH SYNONYMS = ('platform', 'device platform')
        COMMENT = 'Reporting platform of the touch: Mobile Web, Desktop Web, iOS App ...',
    device_platforms.device_type AS device_type
        WITH SYNONYMS = ('device')
        COMMENT = 'Device type of the touch',
    device_platforms.os_group AS os_group
        WITH SYNONYMS = ('operating system', 'os')
        COMMENT = 'Operating system group of the touch'
)

METRICS(
    touchpoints.attributed_subscriptions AS SUM(touchpoints.position_weight)
        WITH SYNONYMS = ('attributed subs', 'credited subscriptions', 'MTA subscriptions')
        COMMENT = 'Subscriptions credited to the touches, position-based model; each subscription adds up to 1',
    touchpoints.paid_attributed_subscriptions AS SUM(touchpoints.paid_position_weight)
        WITH SYNONYMS = ('paid subs', 'paid subscribers', 'paid attributed subscriptions')
        COMMENT = 'Subscriptions credited to paid (8MS / DBS) touches, position-based model',
    touchpoints.signup_touch_attributed_subscriptions AS SUM(touchpoints.signup_touch_weight)
        WITH SYNONYMS = ('sign-up touch model')
        COMMENT = 'Subscriptions credited under the 40 / 40 / 20 model',
    touchpoints.first_touch_subscriptions AS SUM(touchpoints.first_touch_weight)
        WITH SYNONYMS = ('first touch')
        COMMENT = 'Subscriptions credited entirely to the first touch',
    touchpoints.last_touch_subscriptions AS SUM(touchpoints.last_touch_weight)
        WITH SYNONYMS = ('last touch')
        COMMENT = 'Subscriptions credited entirely to the last touch before purchase',
    touchpoints.subscriptions AS COUNT(DISTINCT touchpoints.conversion_id)
        WITH SYNONYMS = ('sign-ups', 'conversions', 'purchases')
        COMMENT = 'Number of subscriptions with a touch in the selection',
    touchpoints.subscriptions_with_paid_touch AS COUNT(DISTINCT touchpoints.paid_conversion_id)
        WITH SYNONYMS = ('paid-touched subscriptions')
        COMMENT = 'Number of subscriptions with at least one paid touch in the selection'
)

COMMENT = 'Click-based subscription attribution: credit, channel, campaign, ad, device, geography and content'
