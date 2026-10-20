# ops

Operational scripts that are run by hand from your machine, not by the scheduled pipeline.

## backfill_page_views.sh

Builds the history of `int_piano__page_views` and `fct_page_views` in monthly chunks. The procedure, and the reasons behind it, are in [Backfilling the Piano page view models](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449#Backfilling-the-Piano-page-view-models) in the DNS Transformations Runbook. This script runs those steps in order so they don't have to be typed month by month:

0. Catches up the four input models (`int_piano__scroll_events`, `int_piano__click_events`, `int_piano__ad_impressions`, `int_piano__event_durations`) with a normal `dbt run`, shows their date range, and asks you to confirm it before going on.
1. Runs the current month, ending tomorrow. This goes first because the scheduled run continues from `MAX(last_event_time)`: once this chunk is in, the nightly run only processes recent days.
2. Runs earlier months, one `dbt run` each, newest first, back to `2024-06` (the first Piano events are from 18 June 2024) or to `--start`.
3. Runs `dbt test` on both models once every chunk is in.

Each chunk is `dbt run --select int_piano__page_views fct_page_views --vars '{piano_backfill_start: …, piano_backfill_end: …}'` (end exclusive). The script never uses `dbt build` or `--full-refresh`.

### When to use it

- The first time history is built on `live`, or after one of the two tables has been dropped to rebuild it.
- To re-run a range of months, for example after an input model was stale. To refresh only the measures in `fct_page_views`, run that month's command by hand with `--select fct_page_views` alone, as the runbook describes; the script always selects both models.

### Usage

Run it from the repository root, with your local profile set up for the target (see the runbook's [Local profile](https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449#Local-profile)).

```bash
ops/backfill_page_views.sh --dry-run
```

Prints every dbt command for the full backfill on `dev` without running anything. Add `--target live` to see the live commands.

```bash
ops/backfill_page_views.sh --target live --confirm-live --max-chunks 4
```

Runs the input catch-up, then the current month and the three before it, then stops and prints the command to continue. `--target live` needs `--confirm-live`, and you are then asked to type `live`.

| Option | Default | |
| --- | --- | --- |
| `--target NAME` | `dev` | dbt target. On `dev`, the input models only hold the last 30 days, so step 0's check shows that. |
| `--confirm-live` | | Required with `--target live` (except with `--dry-run`). |
| `--start YYYY-MM` | `2024-06` | Oldest month to backfill. |
| `--resume-from YYYY-MM` | | Start from this month instead of the current one, then continue with older months. Skips step 0. |
| `--max-chunks N` | no limit | Stop after N chunks and print the command to continue. |
| `--skip-inputs` | | Skip step 0. |
| `--skip-test` | | Skip step 3. |
| `--dry-run` | | Print the commands only. Writes nothing to the log. |

### Resuming after a failure

The script stops at the first chunk that fails and prints the command to resume, for example:

```bash
ops/backfill_page_views.sh --target live --confirm-live --resume-from 2025-03
```

That re-runs the failed month and carries on with older ones. Re-running a chunk is safe: rows merge on `pageview_id`, and each MERGE only touches target rows within two days of the chunk. Don't resume with a month newer than the failed one unless you mean to redo it.

Every run appends to `ops/logs/backfill_page_views.log` (git-ignored): the target, each chunk's range, when it started and finished, how long it took, and whether it failed. Use it to see where a run stopped and how long months take.

### Cost and limits

- **12-hour statement timeout.** A full-history build in one statement hit it, which is why the backfill is chunked. Monthly chunks took under an hour in dev on a Medium warehouse.
- **Daily resource monitor.** The live Medium warehouse (`DNS_TRANSFORMATIONS_PROJECT_TRANSFORMATIONS_GENERAL_MD_WH`) has a daily credit limit, and it also runs the 03:00 UTC pipeline. Spread the backfill over several days with `--max-chunks`, and resume each day with the printed command. If the monitor suspends the warehouse mid-chunk, the chunk fails; resume from it the next day.
- **Larger warehouse.** If the platform team grants a time-boxed larger warehouse for the backfill, point the `warehouse` of your local `live` profile at it while you run the script, then change it back. The scheduled run stays on the Medium warehouse.
- **Remote spill.** If a month starts spilling to remote storage, stop and run it by hand as two half-month chunks, then resume the script from the month before.
