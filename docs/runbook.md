# DNS Transformations Runbook

This runbook is for data analysts & engineers working on the dbt transformations in this repo. We will cover local setup, dev/prod targets, promotion, debugging, and operational contacts. See the [README](../README.md) for project and domain orientation, the [lineage reference](lineage.md) for dependencies and scheduling, and the dbt YAML files linked from the README for model contracts.

## What this project does

The project transforms Piano analytics data in Snowflake into staging, intermediate, and mart models for subscription, engagement, attribution, and reporting use cases. The dbt project lives in the `dbt/` folder. All dbt commands should be run from the `/dbt` folder.

## Local setup

### Prerequisites

- Python 3.13 or later
- `uv` installed and available on `PATH`
- Access to the BBC Snowflake account and the appropriate role
- A local dbt profile at `~/.dbt/profiles.yml` [See dbt documentation for setup instructions](https://docs.getdbt.com/docs/local/profiles.yml)

### Installing uv

If `uv` is not installed, install it with one of the following, then confirm with `uv --version`:

```bash
# macOS / Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# Windows (PowerShell)
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# Alternative: via pip if Python already installed
pip install uv
```

Restart your shell if `uv --version` is not recognized after install.

```bash
exec $SHELL
```


### Setup steps

1. From the repository root, install the environment:

```bash
uv sync # sync packages and dependencies including versioning

source .venv/bin/activate # activate virtual environment
```

2. Install the dbt package dependencies for this project:

```bash
cd dbt # navigate to dbt folder

dbt deps
```
Successful dependency check will output text like `"Up to date!"`

3. Create or modify local `profiles.yml` file located at `~/.dbt/profiles.yml`. This file lives outside the repo and **should not be checked into version control**.

4. Ensure `profiles.yml` contains the same alias used in `profile:` section of `dbt_project.yml`

5. Test the dev and prod target connection with `dbt debug`. This command checks for matching profiles, valid credentials, and connections. Success will be indicated by output like: `"All checks passed!"` in green text.

```bash
dbt debug --target dev #test dev target connection

dbt debug --target prod #test prod target connection
```

### Validate a change locally

Use the smallest practical selection while developing, then run the full checks before opening a pull request:

```bash
cd dbt
dbt compile
dbt build --select <model_name>
dbt build
```

For a model family, use selectors such as `staging.*`, `intermediate.*`, or `marts.*`, or tags. Add `--full-refresh` only when the model requires a rebuild and you understand the cost and impact in the dev schema.

```bash
dbt run --select tag:staging # only run models with staging tag

dbt run -s staging.* # only run only staging models

dbt run -s marts.subscriptions.*  # only run subscription marts
```

## Targets (Dev/Prod)

### Dev

`dev` is the default local target. It writes to the sandbox database and `DNS_DS` schema using the `DNS_DS_PROJECT_ANALYST` role and warehouse shown below. Use it for compilation, model development, and validation.

### Prod

The GitHub Actions environment runs the production target (`prod`) against the production transformation schema. **Do not use `prod` for unvalidated work.**

| Setting   | Dev                            | Prod                                                    |
| --------- | ------------------------------- | -------------------------------------------------------- |
| Account   | `bbcstudios.eu-west-1`          | `bbcstudios.eu-west-1`                                    |
| Database  | `SDP_PROJECT_SANDBOX`           | `SDP_PROJECT_SANDBOX`                                     |
| Schema    | `DNS_DS`                        | `DNS_TRANSFORMATIONS`                                     |
| Role      | `DNS_DS_PROJECT_ANALYST`        | `DNS_TRANSFORMATIONS_PROJECT_TRANSFORMATIONS`             |
| Warehouse | `DNS_DS_PROJECT_GENERAL_MD_WH`  | `DNS_TRANSFORMATIONS_PROJECT_TRANSFORMATIONS_GENERAL_MD_WH` |

This repo is set up to target dev (not prod) by default and writes only to SDP test environment. This logic also applies to the Github Actions workflow in `./github/workflow/run-dbt-pipeline.yml`, so the workflow wil run on the `dev` environment unless a production target is explicitly specified with `--target prod`

## Usage

1. Use the dev target to build models and run tests:

```bash
dbt build # will default to dev sandbox
```

2. Review changes and validate logic.
3. Create a pull request.
4. Merge changes after approval.
5. Promotion to prod:

```bash
dbt build --target prod # deploy to production
```

6. Verify updated tables and monitor for issues post-run.

## Common failures and debugging

### Profile or authentication errors

**Symptoms:** `Could not find profile`, `profiles.yml` invalid, certificate errors, or authentication failures.

**Checks:**

```bash
cd dbt
dbt debug --target dev --debug
```

Confirm that `~/.dbt/profiles.yml` contains the `snowflake` profile, that the target names match the command, and that the certificate and passphrase are available through the approved credential process. **Never** paste secrets into a PR or issue.

### Permission or warehouse errors

**Symptoms:** object does not exist, insufficient privileges, warehouse unavailable, or query timeout.

Confirm the selected target and role. Dev should use `DNS_DS`; prod uses `DNS_TRANSFORMATIONS`. Ask the Snowflake or SDP platform owner to check grants, warehouse state, and quota before changing SQL.

### Compilation or dependency errors

**Symptoms:** Jinja compilation errors, missing macros, or missing package references.

From `dbt/` folder, re-run `dbt deps` in case a package version changed, then re-parse and compile:

```bash
dbt deps
dbt parse --target dev --debug
dbt compile --target dev --debug
```

Check the first error in `target/compiled/` and the corresponding model or macro. Keep generated `target/` output and local logs out of commits unless specifically requested for diagnosis.

### Test failures

Inspect the failing test name and compiled SQL, then reproduce the smallest selection locally:

```bash
dbt test --target dev --select <model_name>
dbt build --target dev --select <model_name>+
```

Distinguish a code regression from changed or late-arriving source data. Record the failing model, test, run ID, target, and first Snowflake error in the pull request or incident thread.

### Schema or numeric type-change failures

Incremental/table replacement behavior can fail when Snowflake cannot alter an existing column type or numeric scale. Compare the current relation schema with the compiled model. Prefer a reviewed migration or targeted full refresh in dev first; never retry a full refresh in prod blindly.

### GitHub Actions failures

Open the failed run and inspect the first failed **Run DBT Task** or **Run DBT Tests** step. Confirm the selected environment is `prod`, review the dbt arguments, and compare the failure with the local `dev` reproduction. The workflow sends transformation notifications; include the GitHub run URL and status when escalating.

## Ownership and contacts

| Area | Owner / contact | How to engage |
| --- | --- | --- |
| dbt models, macros, and seeds | DNS Transformations project maintainers | Open a PR or issue in the [GitHub repository](https://github.com/bbc/dns-transformations-project-transformations) and request review from the current project maintainers. |
| Production workflow and deployment action | SDP deployment/platform team | Escalate with the GitHub Actions run URL, environment, failing step, and first error. |
| Snowflake access, roles, and warehouses | Snowflake / SDP platform support | Provide the target, database, schema, role, warehouse, and timestamp; do not provide credentials. |
| Data quality or source-data issue | Owning source-data team, via the project maintainers | Include affected model, date range, source relation, and a sample query or failing test. |

## Documentation ownership

- README: project orientation, source-system overview, domain meaning, and key outputs.
- [`docs/lineage.md`](lineage.md): current model dependencies, cross-package references, and scheduling order.
- This runbook: local setup, targets, promotion, debugging, and ownership information.
- dbt source YAML files (e.g. `dbt/models/staging/__sources.yml`): declared source definitions.
- dbt model YAML files (marts contracts): model and column contracts.
- Review status: requires review by at least one current team member before being treated as operational guidance.
- [Team wiki](https://onebbc.sharepoint.com/sites/BBCStudios-Analytics)