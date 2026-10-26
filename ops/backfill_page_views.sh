#!/usr/bin/env bash
#
# Chunked historical backfill of the Piano page view models (--mode page-views,
# the default) or the click-based subscription attribution models (--mode attribution).
#
# Follows "Backfilling the Piano page view models" in the DNS Transformations
# Runbook (https://bbcworldwide.atlassian.net/wiki/spaces/CG/pages/7668924449):
#   0. catch up the mode's input models (no vars) and check their date range
#   1. the current month, ending tomorrow, so the nightly watermark is in place
#   2. earlier months, one per dbt run, newest first, back to --start
#   3. dbt test on the chunked models once every chunk is in
# Each chunk is `dbt run` with the mode's backfill vars (end exclusive):
# piano_backfill_start/end or attribution_backfill_start/end. Never `dbt build`
# (it tests the whole table after every chunk) and never --full-refresh. See
# ops/README.md for usage, resuming and cost caveats.

set -euo pipefail

readonly SCRIPT_NAME="ops/backfill_page_views.sh"
readonly HISTORY_START="2024-06"  # first Piano events are from 18 June 2024

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT="${repo_root}"
readonly LOG_DIR="${REPO_ROOT}/ops/logs"

mode="page-views"
target="dev"
confirm_live=false
dry_run=false
start_month="${HISTORY_START}"
resume_from=""
max_chunks=0
skip_inputs=false
skip_test=false

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Backfills the Piano page view models (int_piano__page_views, fct_page_views) or,
with --mode attribution, the incremental attribution models, in monthly chunks:
the current month first, then earlier months newest first, back to --start.

Options:
  --mode MODE            page-views (default) or attribution
  --target NAME          dbt target (default: dev)
  --confirm-live         required with --target live; you are asked to confirm again
  --start YYYY-MM        oldest month to backfill (default: ${HISTORY_START}, the start of history)
  --resume-from YYYY-MM  resume with this month (e.g. the one that failed), then
                         continue with older months; skips the input catch-up
  --max-chunks N         stop after N chunks, to spread the backfill over several days
  --skip-inputs          skip step 0 (input catch-up and date range check)
  --skip-test            skip the final dbt test
  --dry-run              print each dbt command without running anything
  -h, --help             show this help

Chunk start/end times and durations are appended to ops/logs/backfill_<mode>.log.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

# --- arguments ----------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) mode="${2:?--mode needs a value}"; shift 2 ;;
        --target) target="${2:?--target needs a value}"; shift 2 ;;
        --confirm-live) confirm_live=true; shift ;;
        --start) start_month="${2:?--start needs a value}"; shift 2 ;;
        --resume-from) resume_from="${2:?--resume-from needs a value}"; shift 2 ;;
        --max-chunks) max_chunks="${2:?--max-chunks needs a value}"; shift 2 ;;
        --skip-inputs) skip_inputs=true; shift ;;
        --skip-test) skip_test=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "unknown option: $1" ;;
    esac
done

# --- mode ---------------------------------------------------------------------

# CHUNK_MODELS are run once per month with the BACKFILL_VARS; INPUT_MODELS are
# caught up first with a normal run, and INPUT_CHECK_SQL shows their date range.
case "${mode}" in
    page-views)
        readonly MODE_LABEL="Piano page view"
        readonly CHUNK_MODELS=(int_piano__page_views fct_page_views)
        readonly INPUT_MODELS=(int_piano__scroll_events int_piano__click_events int_piano__ad_impressions int_piano__event_durations)
        readonly BACKFILL_VARS=(piano_backfill_start piano_backfill_end)
        readonly INPUT_CHECK_SQL="
select 'scroll' m, min(last_event_time) first_event, max(last_event_time) last_event from {{ ref('int_piano__scroll_events') }}
union all select 'click', min(last_event_time), max(last_event_time) from {{ ref('int_piano__click_events') }}
union all select 'ad', min(last_event_time), max(last_event_time) from {{ ref('int_piano__ad_impressions') }}
union all select 'duration', min(last_event_time), max(last_event_time) from {{ ref('int_piano__event_durations') }}"
        readonly INPUT_CHECK_NOTE="Scroll, click and duration should start on 16 June 2024 (on dev, only the last
30 days), ad on 11 June 2025, and all four should end yesterday or today. If an
input starts later, stop and tell the CGM data team: it needs its own history first."
        ;;
    attribution)
        # The purchases and conversions are rebuilt whole (each journey is bounded by the
        # buyer's previous purchase, in any month), and the chunks read dim_ad.
        readonly MODE_LABEL="Subscription attribution"
        readonly CHUNK_MODELS=(int_attribution__journey_identities int_attribution__journey_touches
            int_attribution__touchpoints int_attribution__touchpoints_source_imputed fct_attribution_touchpoints)
        readonly INPUT_MODELS=(int_attribution__purchase_events int_attribution__conversions stg_google_ads__spend dim_ad)
        readonly BACKFILL_VARS=(attribution_backfill_start attribution_backfill_end)
        readonly INPUT_CHECK_SQL="
select 'conversions' m, min(conversion_date)::timestamp first_event, max(conversion_date)::timestamp last_event from {{ ref('int_attribution__conversions') }}
union all select 'page views', min(page_view_time), max(page_view_time) from {{ ref('int_piano__page_views') }}"
        readonly INPUT_CHECK_NOTE="Conversions should end yesterday or today. Page views must reach back at least
30 days before --start, or the journeys of the oldest months are cut short (on
dev, page views only cover the last 30 days). If they don't, run the page view
backfill first, or pass a later --start."
        ;;
    *) die "--mode must be page-views or attribution, got '${mode}'" ;;
esac
readonly LOG_FILE="${LOG_DIR}/backfill_${mode//-/_}.log"

[[ "${start_month}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "--start must be YYYY-MM, got '${start_month}'"
[[ -z "${resume_from}" || "${resume_from}" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || die "--resume-from must be YYYY-MM, got '${resume_from}'"
[[ "${max_chunks}" =~ ^[0-9]+$ ]] || die "--max-chunks must be a whole number, got '${max_chunks}'"
[[ "${start_month}" < "${HISTORY_START}" ]] && die "--start can't be before ${HISTORY_START}, the start of Piano history"

if [[ "${target}" == "live" && "${confirm_live}" != true && "${dry_run}" != true ]]; then
    die "--target live spends prod credits on the Medium warehouse. Pass --confirm-live to run it."
fi

# --- dates --------------------------------------------------------------------

# Tomorrow as YYYY-MM-DD, with BSD (macOS) or GNU date.
tomorrow() {
    date -v+1d +%Y-%m-%d 2>/dev/null || date -d tomorrow +%Y-%m-%d
}

# The month before YYYY-MM.
previous_month() {
    local year=$((10#${1%-*})) month=$((10#${1#*-}))
    if ((month == 1)); then
        printf '%04d-12\n' $((year - 1))
    else
        printf '%04d-%02d\n' "${year}" $((month - 1))
    fi
}

# The month after YYYY-MM.
next_month() {
    local year=$((10#${1%-*})) month=$((10#${1#*-}))
    if ((month == 12)); then
        printf '%04d-01\n' $((year + 1))
    else
        printf '%04d-%02d\n' "${year}" $((month + 1))
    fi
}

current_month="$(date +%Y-%m)"
readonly current_month
[[ "${start_month}" > "${current_month}" ]] && die "--start ${start_month} is after the current month ${current_month}"
if [[ -n "${resume_from}" ]]; then
    [[ "${resume_from}" > "${current_month}" ]] && die "--resume-from ${resume_from} is after the current month ${current_month}"
    [[ "${resume_from}" < "${start_month}" ]] && die "--resume-from ${resume_from} is before --start ${start_month}"
fi

# --- helpers ------------------------------------------------------------------

# Print a command with arguments that contain spaces quoted, so it can be copied
# into a shell (double quotes for the SQL, which has single quotes in it).
print_command() {
    local arg out=""
    for arg in "$@"; do
        if [[ "${arg}" == *"'"* ]]; then
            out+=" \"${arg}\""
        elif [[ "${arg}" =~ [[:space:]] ]]; then
            out+=" '${arg}'"
        else
            out+=" ${arg}"
        fi
    done
    echo "  \$${out}"
}

log() {
    if [[ "${dry_run}" != true ]]; then
        mkdir -p "${LOG_DIR}"
        echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) target=${target} $*" >>"${LOG_FILE}"
    fi
}

format_duration() {
    printf '%02d:%02d:%02d' $(($1 / 3600)) $(($1 % 3600 / 60)) $(($1 % 60))
}

# Print, then run unless --dry-run.
run() {
    print_command "$@"
    if [[ "${dry_run}" != true ]]; then
        "$@"
    fi
}

resume_hint() {
    local month="$1" hint="${SCRIPT_NAME}"
    [[ "${mode}" != "page-views" ]] && hint+=" --mode ${mode}"
    hint+=" --target ${target}"
    [[ "${target}" == "live" ]] && hint+=" --confirm-live"
    [[ "${start_month}" != "${HISTORY_START}" ]] && hint+=" --start ${start_month}"
    echo "  ${hint} --resume-from ${month}"
}

# --- confirmation -------------------------------------------------------------

cd "${REPO_ROOT}"
[[ -f dbt_project.yml ]] || die "dbt_project.yml not found in ${REPO_ROOT}"

echo "${MODE_LABEL} backfill"
echo "  target:  ${target}"
echo "  months:  ${resume_from:-${current_month}} back to ${start_month} (newest first)"
[[ "${max_chunks}" -gt 0 ]] && echo "  limit:   ${max_chunks} chunk(s) this run"
[[ "${dry_run}" == true ]] && echo "  dry run: commands are printed, nothing is run"
echo

if [[ "${target}" == "live" && "${dry_run}" != true ]]; then
    cat <<EOF
WARNING: this runs dbt against LIVE (SDP_PROJECT_SANDBOX.DNS_TRANSFORMATIONS).
Each monthly chunk spends prod credits on the warehouse in your live profile
(by default DNS_TRANSFORMATIONS_PROJECT_TRANSFORMATIONS_GENERAL_MD_WH), counts
towards its daily resource monitor, and a statement over 12 hours is cancelled.
EOF
    [[ -t 0 ]] || die "a live backfill needs an interactive terminal to confirm"
    read -r -p "Type 'live' to continue: " answer
    [[ "${answer}" == "live" ]] || die "not confirmed, nothing was run"
    echo
fi

# --- step 0: inputs -----------------------------------------------------------

if [[ "${skip_inputs}" != true && -z "${resume_from}" ]]; then
    echo "Step 0: catch up the input models and check their date range"
    log "inputs START"
    run dbt run --target "${target}" --select "${INPUT_MODELS[@]}" || {
        log "inputs FAILED"
        die "catching up the input models failed; nothing was backfilled"
    }
    log "inputs OK"
    run dbt show --target "${target}" --limit -1 --inline "${INPUT_CHECK_SQL}"
    if [[ "${dry_run}" != true ]]; then
        printf '\n%s\n' "${INPUT_CHECK_NOTE}"
        [[ -t 0 ]] || die "can't confirm the input date ranges without a terminal; check them and re-run with --skip-inputs"
        read -r -p "Do the date ranges look right? [y/N] " answer
        [[ "${answer}" =~ ^[Yy]$ ]] || die "stopped before backfilling"
    fi
    echo
fi

# --- steps 1 and 2: chunks ----------------------------------------------------

month="${resume_from:-${current_month}}"
chunks_run=0
while [[ ! "${month}" < "${start_month}" ]]; do
    if [[ "${max_chunks}" -gt 0 && "${chunks_run}" -ge "${max_chunks}" ]]; then
        echo "Stopped after ${chunks_run} chunk(s) (--max-chunks). Continue with:"
        resume_hint "${month}"
        log "paused before ${month} (--max-chunks ${max_chunks})"
        exit 0
    fi

    chunk_start="${month}-01"
    if [[ "${month}" == "${current_month}" ]]; then
        chunk_end="$(tomorrow)"
    else
        chunk_end="$(next_month "${month}")-01"
    fi

    echo "Chunk ${month}: [${chunk_start}, ${chunk_end})"
    log "chunk=${month} range=[${chunk_start},${chunk_end}) START"
    started=${SECONDS}
    if ! run dbt run --target "${target}" --select "${CHUNK_MODELS[@]}" \
        --vars "{${BACKFILL_VARS[0]}: ${chunk_start}, ${BACKFILL_VARS[1]}: ${chunk_end}}"; then
        duration="$(format_duration $((SECONDS - started)))"
        log "chunk=${month} FAILED duration=${duration}"
        echo >&2
        echo "Chunk ${month} failed after ${duration}. Fix the cause, then resume with:" >&2
        resume_hint "${month}" >&2
        exit 1
    fi
    duration="$(format_duration $((SECONDS - started)))"
    log "chunk=${month} OK duration=${duration}"
    [[ "${dry_run}" != true ]] && echo "Chunk ${month} done in ${duration}"
    echo

    chunks_run=$((chunks_run + 1))
    month="$(previous_month "${month}")"
done

# --- step 3: test -------------------------------------------------------------

if [[ "${skip_test}" != true ]]; then
    echo "Step 3: test the backfilled models"
    log "test START"
    started=${SECONDS}
    run dbt test --target "${target}" --select "${CHUNK_MODELS[@]}" || {
        log "test FAILED"
        die "every chunk is in, but dbt test failed; see the output above"
    }
    log "test OK duration=$(format_duration $((SECONDS - started)))"
fi

log "backfill complete back to ${start_month}"
echo "Backfill complete back to ${start_month}."
if [[ "${mode}" == "attribution" ]]; then
    echo "The tables built from these models (dim_channel, dim_campaign_tracking,"
    echo "agg_subscription_attribution_touchpoint, fct_conversions and everything after it)"
    echo "pick up the history at the next scheduled run."
fi
