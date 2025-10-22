# DNS Transformations Project - Transformations

This repository contains a minimal [dbt](https://docs.getdbt.com/) project and a GitHub Actions workflow that demonstrates how to:

- Connect securely to Snowflake using a machine user and certificate-based authentication
- Run `dbt` commands in CI/CD via a reusable composite GitHub Action
- Materialise a simple `hello_world` table in Snowflake to confirm end-to-end connectivity

It can be used as a template or reference for setting up your own DBT automation.

## 🛠️ Setting Up Your Own Project

Pre-requisite: Ensure you have a project sandbox created.

- You can request a new project sandbox via the form available here: [Project Sandbox Request Form](<https://onebbc.sharepoint.com/sites/bbcs-CommercialDataProducts/SitePages/Request-for-Collaborative-Space(1).aspx?csf=1&web=1&e=txQzic&CID=6c69eb9a-e146-45dc-8c11-3851314126e1>)

You have two options to get started:

### Option 1: Use this repository as a template

1. Click **"Use this template"** in the top-right corner of the repository.
2. Create your own copy under your GitHub account or organisation.
3. Add `Studios Data Platform` as admins to the repository. This will allow us to input the [🔐 Required GitHub Secrets](#-required-github-secrets).
4. Request the Studios Data Platform Team to create a GitHub runner for the repository.
5. Add your own DBT files and models to the `dbt/` directory.
6. Modify the workflow file if needed: `.github/workflows/run_dbt_pipeline.yml`.
7. Trigger the workflow manually or via a schedule.

### Option 2: Copy parts into an existing repository

1. Add `Studios Data Platform` as admins to the repository. This will allow us to input the [🔐 Required GitHub Secrets](#-required-github-secrets).
2. Request the Studios Data Platform Team to create a GitHub runner for the repository.
3. Copy the `dbt/` directory and its contents into your repository.
4. Add your DBT models and project files under `dbt/`.
5. Copy `.github/workflows/run_dbt_pipeline.yml` into your repo’s workflows directory.
6. Ensure you are referencing the `run-dbt-task/` in order to reuse the modular job logic.
7. Trigger the workflow manually or via a schedule.

> ✅ The only hard requirement is that your DBT project lives under a `dbt/` directory so that the workflow and composite action can locate it.

## 📁 Project Structure

```
├── dbt/
│   ├── dbt_project.yml          # DBT project config
│   └── models/
│       ├── hello_world.sql      # Simple test model that creates a table
│       └── schema.yml           # (Optional) Metadata for the model
├── .github/
│   └── workflows/
│       └── run_dbt_pipeline.yml # Workflow that triggers the DBT job
```

## 🚀 How it works

The GitHub Actions workflow (`run_dbt_pipeline.yml`) uses a composite action (`run-dbt-task`) that performs the following steps:

1. Sets up a valid `profiles.yml` for Snowflake authentication using a base64-encoded private key
2. Installs `dbt` and dependencies
3. Runs `dbt parse` and `dbt debug` to validate the project and connection
4. Executes a `dbt run` to create a simple test table

## 🔐 Required GitHub Secrets

To securely authenticate with Snowflake, the following repository secrets must be defined:

| Secret                   | Description                                             |
| ------------------------ | ------------------------------------------------------- |
| `SNOWFLAKE_ACCOUNT`      | Snowflake account identifier (e.g. `xy12345.eu-west-1`) |
| `SNOWFLAKE_MACHINE_USER` | Machine user name                                       |
| `SNOWFLAKE_ROLE`         | Role to execute the DBT job with                        |
| `SNOWFLAKE_CERT`         | Base64-encoded private key (`.p8` file)                 |
| `SNOWFLAKE_CERT_PASS`    | Passphrase for the private key                          |
| `SNOWFLAKE_DATABASE`     | Target database                                         |
| `SNOWFLAKE_WAREHOUSE`    | Target warehouse                                        |
| `SNOWFLAKE_SCHEMA`       | Target schema                                           |
| `DEPLOYMENTS_API_KEY`    | API key for the deployments api for notifications       |

## 🧪 The Test Model: `hello_world`

This project contains a single DBT model located at `dbt/models/hello_world.sql`:

```sql
-- hello_world.sql
select 'hello world' as greeting
```

When the workflow runs, this model is materialised as a table in your configured Snowflake schema:

```sql
-- Example output:
select * from <DATABASE>.<SCHEMA>.hello_world;

-- Result:
| greeting     |
|--------------|
| hello world  |
```

## ✅ Running the Workflow

You can trigger the pipeline in two ways:

- Manually: via the "Run workflow" button in the GitHub Actions tab
- Scheduled: via cron specified within the workflow, for example: every day at 2:00 AM UTC - (`0 2 * * *`)
