# DNS Transformations Project - Transformations

This repository contains the dbt project for transforming Piano analytics data into a structured dimensional model for subscription, engagement, attribution, and reporting use cases.

## Lineage

See the [DNS Transformations lineage overview](docs/lineage.md) for full source-to-mart flow, source and model names, and cross-DAG/cross-project references.

## Runbook

See the [DNS Transformations runbook](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449/DNS+Transformations+Runbook) for local setup, dev/prod targets, dev -> prod promotion, debugging, and ownership information.

## Data model

The project follows a layered modelling approach:

1. **Staging (`dbt/models/staging`)**: Light-touch cleaning, type casting, standardisation, URL parameter extraction, and source-specific filtering. Key models include `stg_piano__composer_events`, `stg_piano__analytics_events`, `stg_piano__offsite_events`, `stg_subscription_attribution`, `stg_meta_google_spend_subs`, and `stg_piano__subscription_snapshots`.
2. **Intermediate (`dbt/models/intermediate`)**: Reusable transformations for conversion attribution, exposure deduplication, subscription status, multi-touch attribution, and survival analysis.
3. **Marts (`dbt/models/marts`)**: User-facing facts, dimensions, attribution outputs, engagement models, reporting aggregates, and Salesforce outputs.

### Data sources

| Source | Database | Schema | Description |
| --- | --- | --- | --- |
| `studios_piano_events` | `sdp_silver` | `studios_piano` | Piano events from the current BBC Studios organisation |
| `ps_piano_events` | `sdp_bronze` | `ps_piano` | Piano events from the previous BBC piano org. Declared in sources but not currently read by any active model — see the [lineage inventory](docs/lineage.md#declared-sources-without-a-current-downstream-model). |
| `basic_ad` | `sdp_bronze` | `FACEBOOK_ADS` | Facebook Ads data |
| `STG_GOOGLE_ADS` | `sdp_project_sandbox` | `GOOGLE_ADS` | Google Ads data |
| `piano_subscription_snapshots` | `sdp_project_sandbox` | `dns_transformations` | Daily Piano API subscription snapshot upload |
| `sfmc_*` | `sdp_silver` | `salesforce_brands_licencing_crm` | Salesforce Marketing Cloud email, journey, and subscriber data |

The complete source list, including table descriptions and sources not currently utilized by a model, is maintained in [`dbt/models/staging/__sources.yml`](dbt/models/staging/__sources.yml). For sources without an explicit schema in that file, dbt uses the configured profile default. The active source-to-model relationships are maintained in the [lineage inventory](docs/lineage.md#complete-model-dependency-inventory).


### Core subscription outputs

| Model | Grain or purpose |
| --- | --- |
| `fact_conversions` | Conversion touchpoints, including subscription, visitor, Piano experience, revenue, device, geography, and attribution fields |
| `fact_exposures` | Piano experience exposure events, including visitor/session, experience, template, device, app, OS, and paid-exposure fields |
| `fact_subscription_events` | Subscription lifecycle events such as new subscription, renewal, cancellation, expiry, and failed renewal |
| `fact_subscriber_daily_snapshot` | One row per subscription and date, tracking status, current term, MRR, conversion age, and geography |
| `fact_subscriber_activity_daily` | Daily subscriber activity derived from subscription snapshots and Piano analytics events |
| `fact_cohort_retention` | Cohort-month retention counts by months since conversion |
| `dim_subscription` | Subscription reference dimension, built from current Piano subscription state and subscription lifecycle events |
| `dim_experience` | Piano Composer experience reference dimension |
| `dim_template` | Piano template reference dimension and template type |
| `dim_term` | Subscription term, billing period, and offer reference dimension |
| `marketing_spend_subs` | Facebook and Google ad spend, joined for subscription marketing reporting |

### Audience, reporting, and operational outputs

| Model | Purpose |
| --- | --- |
| `fact_visitors_daily` | Daily visitor counts by date, geography, app type, device type, and operating system group |
| `agg_acquisition_funnel_daily` | Daily acquisition funnel aggregates across exposures, visitors, and conversions |
| `agg_acquisition_signups_daily` | Daily sign-up aggregates with attribution weighting and audience dimensions |
| `agg_engaged_subscribers_monthly` / `agg_engaged_subscribers_weekly` | Engaged subscriber reporting by period |
| `agg_subs_content_1w_snapshot` / `agg_subs_pillar_views_l30d_snapshot` / `agg_subs_product_usage_30d_snapshot` | Subscription content and product usage snapshots |
| `agg_subscriber_bans` | Subscriber ban and exclusion reporting |
| `bbc_com_semantic_view_dbt` | Semantic reporting view built from conversion and subscription marts |
| `sfmc_journey_send_job` | Salesforce Marketing Cloud journey send output |

The [lineage overview](docs/lineage.md) is documents current model names, direct dependencies, cross-package references, and scheduling order.

Column-level descriptions, types, tests, and relationship contracts are maintained in the dbt YAML files rather than duplicated here:

- [Core model schema](dbt/models/marts/core/_core__models.yml)
- [Subscription model schema](dbt/models/marts/subscription/_subscription__models.yml)
- [Engagement model schema](dbt/models/marts/engagement/_engagement__models.yml)
- [Reporting model schema](dbt/models/marts/reporting/_reporting__models.yml)


## Attribution

The `int_subscription_attribution` model identifies valid sign-ups, paid touchpoints, first and last events, and promo-code paths. Its position-based weighting is:

- No promo code: 40% first touch, 40% last touch, and 20% distributed across middle touches.
- Promo code path: 30% first touch, 30% last touch, 30% promo or paid touch, and 10% distributed across remaining touches, with special handling for short paths.

The downstream `int_subscription_attribution_src_corrected` model redistributes NULL attribution sources proportionally and formats generic search-engine sources. The `subscription_attribution_model` applies attribution-weighted revenue, annualises non-yearly billing periods, and incorporates subscription lifetime or renewal information.

## Seeds

| Seed | Purpose |
| --- | --- |
| `experience_app_type` | Maps mobile app experience IDs and names to app types |
| `geo_mapping` | Geography reference data |
| `piano_retention_curves` | Expected retention curves for survival-analysis benchmarking

Seed definitions and column tests are maintained in [`dbt/seeds/schema.yml`](dbt/seeds/schema.yml). Seed changes are promoted through the workflow described in the [runbook](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449/DNS+Transformations+Runbook#Usage).

## Analyses

The `dbt/analyses/` directory contains exploratory queries that build on mart tables. [`survival_data.sql`](dbt/analyses/survival_data.sql) prepares subscriber survival-analysis data from subscription events, including tenure duration and churn status.

## Development

This is a quickstart only guide - [DNS Transformations Runbook (Confluence)](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449/DNS+Transformations+Runbook) is definitive for local setup, environment installation, and command reference.

Key commands:
```bash
uv sync # install dependencies
source .venv/bin/activate # activate virtual environment
cd dbt # navigate to dbt folder
dbt debug --target dev # test connection
dbt deps # install dbt dependencies
dbt run -s staging.* # Run only staging models
dbt run -s marts.subscriptions.* # Run only subscription marts
dbt run # Execute all models
dbt test # Run all data and schema tests
dbt build # Run models and tests together
```

Use the `dev` target for local validation. **Do not target `prod` with unverified/unvalidated code**; Please follow the [promotion and prod workflow process](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449/DNS+Transformations+Runbook#Usage) in the runbook.

## Documentation ownership

Documentation is distributed by audience and topic. Use the document listed as authoritative for that topic:

| Topic | Authoritative location | What belongs there |
| --- | --- | --- |
| Project orientation and domain context | This README | Purpose, source-system overview, layer descriptions, key outputs, attribution concepts, seeds, and analyses |
| Declared source definitions | [`dbt/models/staging/__sources.yml`](dbt/models/staging/__sources.yml) | Exact source databases, schemas, tables, and source descriptions |
| Model dependencies and scheduling | [`docs/lineage.md`](docs/lineage.md) | Current model names, direct upstream dependencies, cross-package boundaries, and build order |
| Model and column contracts | Linked dbt YAML files above | Column descriptions, data types, tests, and relationships |
| Local development and deployment operations | [DNS Transformations Runbook (Confluence)](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449/DNS+Transformations+Runbook) | Setup, commands, dev/prod targets, promotion, failure diagnosis, and contacts |