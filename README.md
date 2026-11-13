# DNS Transformations Project - Transformations

The dbt project behind the BBC.com data model. It transforms Piano analytics, marketing and CRM data in Snowflake into facts, dimensions and aggregates for subscription, engagement, attribution and reporting use cases.

## Documentation

Team documentation lives in Confluence, in the **BBC.com Data Model** folder of the Consumer Growth space. Start at [Start here](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7673610241/Start+here).

| Topic | Where |
| --- | --- |
| Installing dbt, profiles, VS Code | [Getting set up](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7672987651/Getting+set+up) |
| Branching, commands, pull requests | [Development workflow](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7625572408/Development+workflow) |
| Layers, naming, SQL style, tests | [dbt Modelling Standards](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7627014156/dbt+Modelling+Standards) |
| Environments, pipeline, production releases, incidents, contacts | [DNS Transformations Runbook](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449/DNS+Transformations+Runbook) |
| What each fact, dimension and aggregate means | [Models](https://bbcworldwide.atlassian.net/wiki/spaces/CG/folder/7672725513) |
| Model dependencies and scheduling order | [`docs/lineage.md`](docs/lineage.md) |
| Columns, tests and source definitions | The YAML files next to the models (see below) |
| Guidance for AI coding agents, and which docs to update with each change | [`AGENTS.md`](AGENTS.md) |

## Repository layout

| Path | Contains |
| --- | --- |
| `models/bronze/<source>/` | Source declarations (`_<source>__sources.yml`) and staging models (`stg_`) |
| `models/silver/intermediate/<domain>/` | Intermediate models (`int_`) |
| `models/silver/facts/` | Facts (`fct_`) |
| `models/silver/dims/` | Dimensions (`dim_`) |
| `models/gold/aggregates/` | Aggregates (`agg_`) |
| `macros/` | Reusable SQL logic |
| `seeds/` | Reference data, documented and tested in [`seeds/schema.yml`](seeds/schema.yml) |
| `analyses/` | Exploratory queries built on the facts |
| `docs/lineage.md` | Dependency diagrams and model inventory |
| `.sqlfluff` | SQL style rules enforced by `dbt lint` in CI |

Model YAML sits next to the models as `_<folder>__models.yml`.

## Quickstart

Once you've followed [Getting set up](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7672987651/Getting+set+up), run from the repository root:

```bash
dbt deps                          # install packages
dbt debug                         # check the dev connection
dbt lint --changed                # check SQL style
dbt build --select <model_name>+  # build and test a model and its downstream models on dev
```

Develop against `dev`, the default target. `dev` is rebuilt from `main` every night at 03:00 UTC by [dns-ds-transformations](https://github.com/bbc/dns-ds-transformations), which overwrites feature-branch tables, so rebuild yours with `dbt build --select <model>+`. Production (the `live` target) is updated by the scheduled pipeline; see the [runbook](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449/DNS+Transformations+Runbook#Getting-changes-into-production).
