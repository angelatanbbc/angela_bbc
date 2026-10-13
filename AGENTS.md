# AGENTS.md

Guidance for AI coding agents working in this repository. Human-facing documentation lives in Confluence; this file is a map to it plus the few rules agents most often get wrong. Read the linked pages rather than relying on this summary, and don't copy their content here.

## What this repo is

The `dns_transformations` dbt project (dbt Fusion, Snowflake) that builds the BBC.com data model for the CGM team from Piano, marketing and CRM data. The dbt project is at the repository root.

| Folder | Contains | Selector |
| --- | --- | --- |
| `models/bronze/<source>/` | Sources (`_<source>__sources.yml`) and staging models (`stg_`) | `bronze` |
| `models/silver/intermediate/<domain>/` | Intermediate models (`int_`) | `silver.intermediate` |
| `models/silver/facts/` | Facts (`fct_`) | `silver.facts` |
| `models/silver/dims/` | Dimensions (`dim_`) | `silver.dims` |
| `models/gold/aggregates/` | Aggregates (`agg_`) | `gold.aggregates` |

Model YAML sits next to the models as `_<folder>__models.yml`.

## Documentation map

All pages are in the Consumer Growth (`CG`) space on `bbcworldwide.atlassian.net`, under the **BBC.com Data Model** folder.

| Page | Owns | Link |
| --- | --- | --- |
| Start here | Reading order, what lives where | [7673610241](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7673610241) |
| Getting set up | Installing dbt and tools, profiles, VS Code | [7672987651](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7672987651) |
| Development workflow | Branching, commands, PR checklist, definition of done | [7625572408](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7625572408) |
| dbt Modelling Standards | Layers, naming, SQL style and lint rules, tests, docs | [7627014156](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7627014156) |
| DNS Transformations Runbook | Environments, CI workflows, production releases, incidents, contacts | [7668924449](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449) |
| Models (folder) | One page per fact, dim, aggregate and semantic view | [7672725513](https://bbcworldwide.atlassian.net/wiki/spaces/CG/folder/7672725513) |
| Model page template | Structure for new Models pages | [7672659982](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7672659982) |

In the repo: `README.md` (domain orientation), `docs/lineage.md` (dependencies and scheduling), model YAML (column descriptions and tests).

Before writing or reviewing SQL, read **dbt Modelling Standards**. Before documenting a model, read the **Model page template** and an existing page in **Models** (for example `fct_conversions`).

## Rules

- Run dbt commands from the repository root. The default target is `dev`.
- **Never** run `--target prod` builds, seeds or full refreshes. Production is updated by the scheduled pipeline (see the runbook). Read-only queries against prod (`dbt show --target prod`) are fine when the user has asked for them.
- Before finishing a SQL change, run `dbt parse`, `dbt lint --changed`, and where possible `dbt build --select <model>+`. CI fails pull requests on lint errors. `.sqlfluff` is the source of truth for enforced style.
- Put new models in the folder for their layer and follow the naming conventions above.
- Branch from `main` as `feature/CGM-<ticket>-<description>` or `fix/<description>`, and fill in `pull-request-template.md`.

## Keep the docs in step with the code

Update documentation in the same pull request as the change:

| If you change | Also update |
| --- | --- |
| Columns, tests or descriptions | The model's `_<folder>__models.yml` |
| Meaning, grain, metrics, build logic or caveats of a fact, dim, aggregate or semantic view | Its page in **Models** (add a Change history row linking the PR); create one from the template for a new model |
| Model dependencies | `docs/lineage.md` |
| CI workflows, environments, roles, schedules or contacts | The **DNS Transformations Runbook** |
| Setup steps, commands or workflow | **Getting set up** or **Development workflow** |
| Style or naming rules (including `.sqlfluff`) | **dbt Modelling Standards** |

Mention the doc updates in the pull request description, or say why none were needed.

## Working with Confluence

This repo ships `.mcp.json`, which registers the Atlassian Rovo MCP server (`https://mcp.atlassian.com/v2/mcp`). In Claude Code, approve it when prompted, then run `/mcp` and sign in with your Atlassian account. Other clients: see Atlassian's [getting started guide](https://support.atlassian.com/rovo/docs/getting-started-with-the-atlassian-remote-mcp-server/) (Codex: `codex mcp add atlassian --url https://mcp.atlassian.com/v2/mcp`).

When editing pages:

- Read the page first (HTML format) and edit the sections you need by node, rather than replacing the whole body. Preserve macros, smart links and other people's edits.
- Follow the existing structure and tone. New Models pages copy the template and keep its Page Properties block.
- Add a short version message describing the change.
- Link pages by URL or page ID, never by copying their content.
