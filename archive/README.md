# Archive

Models kept for reference only. This folder is outside `model-paths` in `dbt_project.yml`, so dbt never parses or builds anything in it. To bring a model back, move it under `models/` again.

| Folder | What | Archived | Replaced by |
| --- | --- | --- | --- |
| `old_attribution/` | The old click-based subscription attribution: `stg_piano__subscription_attribution`, `int_subscription__attribution`, `int_subscription__attribution_src_corrected`, `fct_subscription_attribution` | October 2026 (CGM-1633) | `fct_attribution_touchpoints` and `agg_subscription_attribution_touchpoint` |

The archived models' tables are still in the live schema but are no longer updated.
