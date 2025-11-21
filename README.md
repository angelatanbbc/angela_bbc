# DNS Transformations Project - Transformations

This repository contains the dbt project for transforming Piano analytics data into a structured dimensional model, ready for analysis. The primary goal is to model user behavior, subscription events, and exposure to on-site experiences.

## 📈 The Data Model

This dbt project follows a layered data modeling approach to systematically progress data from its raw source format to clean, well-documented, and analysis-ready tables.

The layers are organized as follows:

1.  **Staging (`models/staging`)**: Models in this layer perform light-touch cleaning of the source data. This includes column renaming, type casting, and basic transformations to create a consistent foundation for downstream models. Each staging model generally corresponds to a single source table.

2.  **Intermediate (`models/intermediate`)**: This layer contains more complex transformations. Models here often join multiple staging models, apply business logic, and aggregate data to create building blocks for the final mart tables. For example, user sessions might be reconstructed here.

3.  **Marts (`models/marts`)**: These are the final, user-facing models. They are designed for specific business purposes and are structured as fact and dimension tables. These tables are what data consumers (analysts, data scientists, BI tools) will query directly.

### Data Flow Diagram

Here is a high-level overview of the data flow through the dbt project:

```mermaid
graph TD
    subgraph Raw Sources
        A[src_studios_piano_events]
        B[src_ps_piano_events]
    end

    subgraph Staging Layer
        C(stg_piano_events)
    end

    subgraph Intermediate Layer
        D(int_sessionized_events)
        E(int_subscription_lifecycle)
    end

    subgraph Marts Layer
        F[dim_users]
        G[dim_visits]
        H[dim_experiences]
        I[fact_conversions]
        J[fact_exposures]
        K[fact_subscription_events]
    end

    A --> C
    B --> C
    C --> D
    C --> E
    D --> G
    D --> I
    D --> J
    E --> K
    I --> F
    J --> F
    I --> G
    J --> G
    I --> H
    J --> H
```

### Dimensional Model

The marts layer is organized as a dimensional model to facilitate analytics on key business processes. The core components are fact tables, which store events and metrics, and dimension tables, which provide descriptive context.

#### Fact Tables

- `fact_conversions`: An event-based fact table where each row represents a single subscription conversion. It captures key details about the conversion, such as the promo code used, billing period, and the Composer experience that drove it.
- `fact_exposures`: A daily snapshot fact table that aggregates user exposures to Composer experiences. It counts the number of times a user was exposed to or interacted with a specific A/B test variant on a given day.
- `fact_subscription_events`: An event-based fact table that logs the entire lifecycle of a subscription. It includes events like 'New Subscription', 'Canceled', and 'Expired', which is crucial for churn and survival analysis.

#### Dimension Tables

While not explicitly defined in the provided files, the fact tables are designed to be joined with dimension tables such as:

- `dim_users`: Contains information about registered users.
- `dim_visits`: Contains details about a user's visit (session), such as start time and landing page.
- `dim_experiences`: A dimension for Composer experiences, containing details about the experience, template, and A/B test variant.

### Marts Schema Diagram

The relationship between the core fact and dimension tables can be visualized as a star schema.

```mermaid
erDiagram
    fact_conversions {
        string conversion_id PK
        string subscription_id FK
        string visitor_id FK
        string user_id FK
        string visit_id FK
        string experience_id FK
        timestamp conversion_time
        string billing_period
    }
    fact_exposures {
        string exposure_id PK
        string visit_id FK
        string visitor_id FK
        string user_id FK
        string experience_id FK
        date exposure_date
        int count_exposures
        int count_interactions
    }
    dim_users {
        string user_id PK
        string visitor_id
        string c1x_lts
    }
    dim_visits {
        string visit_id PK
        string visitor_id
        timestamp visit_time
    }
    dim_experiences {
        string experience_id PK
        string template_id
        string ab_test_variant_name
    }

    fact_conversions }o--|| dim_users : "by"
    fact_conversions }o--|| dim_visits : "during"
    fact_conversions }o--|| dim_experiences : "driven by"

    fact_exposures }o--|| dim_users : "by"
    fact_exposures }o--|| dim_visits : "during"
    fact_exposures }o--|| dim_experiences : "of"
```

## 🔬 Analyses

The `analyses/` directory contains exploratory queries and scripts that leverage the mart tables. An example is `survival_data.sql`, which uses `fact_subscription_events` to prepare data for a subscriber survival analysis, calculating tenure duration and churn status for each subscription.

## ⚙️ Development

To run this dbt project locally, ensure you have a `profiles.yml` file configured for your Snowflake connection. Refer to the dbt documentation for setup instructions.

Key commands:

- `dbt run`: Executes all models.
- `dbt test`: Runs all data and schema tests.
- `dbt build`: Runs models and tests.
