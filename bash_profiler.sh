#!/usr/bin/env bash

###############################################################################
# bash_profiler.sh
#
# Run an R script on macOS while monitoring:
#
# - The Rscript process and its descendants
# - Ollama processes
# - Per-process CPU and resident memory
# - Aggregate R and Ollama CPU and memory
# - Estimated available system memory
# - R console-output growth
# - Ollama-log growth, when a standard log can be found
# - Ollama model state
#
# Usage:
#
#   ./bash_profiler.sh
#
# Optional arguments:
#
#   ./bash_profiler.sh <R script> <output directory> <interval> <timeout>
#
# Example:
#
#   ./bash_profiler.sh SampleUser.R diagnostics 2 1800
#
# Arguments:
#
#   1. R script path                 default: SampleUser.R
#   2. Diagnostic parent directory   default: diagnostics
#   3. Sampling interval in seconds  default: 2
#   4. Timeout in seconds            default: 1800
#
# A timeout of 0 disables the timeout.
#
# Privacy warning:
#
# R console output is written to r_console.log. Do not print sensitive source
# records, prompts, payloads, or model responses from SampleUser.R unless the
# diagnostic directory is an approved location.
###############################################################################

# Do not use `set -e`. Some monitoring commands legitimately return nonzero
# when a process disappears between sampling operations.
set -u
set -o pipefail


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

R_SCRIPT="${1:-SampleUser.R}"
OUTPUT_PARENT="${2:-diagnostics}"
SAMPLE_INTERVAL="${3:-2}"
TIMEOUT_SECONDS="${4:-1800}"

PROJECT_DIR="$(pwd)"

RUN_TIMESTAMP="$(date -u '+%Y%m%d_%H%M%S')"
RUN_ID="sample_user_${RUN_TIMESTAMP}"
RUN_DIR="${OUTPUT_PARENT}/${RUN_ID}"

R_CONSOLE_LOG="${RUN_DIR}/r_console.log"
PROCESS_LOG="${RUN_DIR}/process_samples.csv"
AGGREGATE_LOG="${RUN_DIR}/aggregate_samples.csv"
SYSTEM_LOG="${RUN_DIR}/system_samples.csv"
OLLAMA_PS_LOG="${RUN_DIR}/ollama_ps.log"
DIAGNOSTIC_REPORT="${RUN_DIR}/diagnostic_report.txt"
RUN_METADATA="${RUN_DIR}/run_metadata.txt"

TIMED_OUT=0
INTERRUPTED=0
R_EXIT_STATUS=NA


# ---------------------------------------------------------------------------
# Basic validation
# ---------------------------------------------------------------------------

if [[ ! -f "${R_SCRIPT}" ]]; then
    echo "ERROR: R script not found: ${R_SCRIPT}" >&2
    exit 1
fi

if ! command -v Rscript >/dev/null 2>&1; then
    echo "ERROR: Rscript could not be found on PATH." >&2
    echo "Try running: which Rscript" >&2
    exit 1
fi

if ! [[ "${SAMPLE_INTERVAL}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "ERROR: Sampling interval must be a positive number." >&2
    exit 1
fi

if ! awk -v value="${SAMPLE_INTERVAL}" \
    'BEGIN { exit !(value > 0) }'; then
    echo "ERROR: Sampling interval must be greater than zero." >&2
    exit 1
fi

if ! [[ "${TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Timeout must be a nonnegative whole number." >&2
    exit 1
fi

mkdir -p "${RUN_DIR}"


# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

timestamp_iso() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}


format_epoch_utc() {
    local epoch_value="$1"

    date -u -r "${epoch_value}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
        printf '%s\n' "unknown"
}


file_size_bytes() {
    local file_path="$1"

    if [[ -f "${file_path}" ]]; then
        stat -f '%z' "${file_path}" 2>/dev/null || echo 0
    else
        echo 0
    fi
}


file_age_seconds() {
    local file_path="$1"
    local now_epoch
    local modified_epoch

    if [[ ! -f "${file_path}" ]]; then
        echo -1
        return
    fi

    now_epoch="$(date '+%s')"

    modified_epoch="$(
        stat -f '%m' "${file_path}" 2>/dev/null ||
            echo "${now_epoch}"
    )"

    echo $((now_epoch - modified_epoch))
}


sanitize_csv_text() {
    # Replace commas, quotes, and line breaks so a command does not corrupt
    # the simple CSV output.
    printf '%s' "$1" |
        tr '\n\r' '  ' |
        sed 's/,/;/g; s/"/'\''/g'
}


find_ollama_log() {
    local candidates=(
        "${HOME}/.ollama/logs/server.log"
        "${HOME}/Library/Logs/Ollama/server.log"
        "${HOME}/Library/Application Support/Ollama/server.log"
    )

    local candidate

    for candidate in "${candidates[@]}"; do
        if [[ -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return
        fi
    done

    printf '%s\n' ""
}


collect_descendants() {
    # Print the root process and all descendants, one PID per line.
    local root_pid="$1"
    local queue="${root_pid}"
    local collected="${root_pid}"
    local parent_pid
    local child_pids
    local child_pid

    while [[ -n "${queue}" ]]; do
        parent_pid="${queue%% *}"

        if [[ "${queue}" == *" "* ]]; then
            queue="${queue#* }"
        else
            queue=""
        fi

        child_pids="$(
            pgrep -P "${parent_pid}" 2>/dev/null ||
                true
        )"

        for child_pid in ${child_pids}; do
            if ! printf '%s\n' "${collected}" |
                tr ' ' '\n' |
                grep -qx "${child_pid}"; then

                collected="${collected} ${child_pid}"

                if [[ -n "${queue}" ]]; then
                    queue="${queue} ${child_pid}"
                else
                    queue="${child_pid}"
                fi
            fi
        done
    done

    printf '%s\n' "${collected}" |
        tr ' ' '\n' |
        awk 'NF > 0' |
        sort -n -u
}


collect_ollama_pids() {
    # Select processes whose executable basename begins with "ollama".
    ps -axo pid=,comm= 2>/dev/null |
        awk '
        {
            pid = $1
            command = $2

            count = split(command, parts, "/")
            basename = tolower(parts[count])

            if (basename ~ /^ollama/) {
                print pid
            }
        }
        ' |
        sort -n -u
}


pid_in_list() {
    local target_pid="$1"
    local pid_list="$2"

    printf '%s\n' "${pid_list}" |
        grep -qx "${target_pid}"
}


numeric_or_zero() {
    local value="${1:-0}"

    if [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s\n' "${value}"
    else
        printf '%s\n' "0"
    fi
}


integer_or_zero() {
    local value="${1:-0}"

    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "${value}"
    else
        printf '%s\n' "0"
    fi
}


system_memory_sample() {
    # Return:
    #
    # total_mb,available_estimate_mb,memory_free_percent
    #
    # available_estimate_mb is estimated from free, inactive, and
    # speculative pages reported by macOS vm_stat.
    #
    # The calculations use awk instead of Bash integer arithmetic. This avoids
    # problems with large values, leading zeroes, and incorrect use of command
    # substitution.

    local total_bytes
    local total_mb
    local vm_output
    local page_size
    local free_pages
    local inactive_pages
    local speculative_pages
    local available_mb
    local free_percent

    total_bytes="$(
        sysctl -n hw.memsize 2>/dev/null ||
            echo 0
    )"

    total_bytes="$(integer_or_zero "${total_bytes}")"

    total_mb="$(
        awk -v bytes="${total_bytes}" '
        BEGIN {
            printf "%.0f", bytes / 1024 / 1024
        }
        '
    )"

    vm_output="$(
        vm_stat 2>/dev/null ||
            true
    )"

    page_size="$(
        printf '%s\n' "${vm_output}" |
            head -n 1 |
            sed -E 's/.*page size of ([0-9]+) bytes.*/\1/'
    )"

    if ! [[ "${page_size}" =~ ^[0-9]+$ ]]; then
        page_size=4096
    fi

    free_pages="$(
        printf '%s\n' "${vm_output}" |
            awk '
            /Pages free:/ {
                gsub("\\.", "", $3)
                print $3
            }
            '
    )"

    inactive_pages="$(
        printf '%s\n' "${vm_output}" |
            awk '
            /Pages inactive:/ {
                gsub("\\.", "", $3)
                print $3
            }
            '
    )"

    speculative_pages="$(
        printf '%s\n' "${vm_output}" |
            awk '
            /Pages speculative:/ {
                gsub("\\.", "", $3)
                print $3
            }
            '
    )"

    free_pages="$(integer_or_zero "${free_pages}")"
    inactive_pages="$(integer_or_zero "${inactive_pages}")"
    speculative_pages="$(integer_or_zero "${speculative_pages}")"
    page_size="$(integer_or_zero "${page_size}")"

    available_mb="$(
        awk \
            -v free_pages="${free_pages}" \
            -v inactive_pages="${inactive_pages}" \
            -v speculative_pages="${speculative_pages}" \
            -v page_size="${page_size}" '
        BEGIN {
            available_pages = free_pages + inactive_pages + speculative_pages
            available_bytes = available_pages * page_size

            printf "%.0f", available_bytes / 1024 / 1024
        }
        '
    )"

    free_percent="$(
        memory_pressure -Q 2>/dev/null |
            awk -F: '
            /System-wide memory free percentage/ {
                gsub(/%/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                print $2
            }
            '
    )"

    free_percent="${free_percent:-NA}"

    printf '%s,%s,%s\n' \
        "${total_mb}" \
        "${available_mb}" \
        "${free_percent}"
}


snapshot_ollama_ps() {
    {
        echo ""
        echo "========================================================================"
        echo "Timestamp: $(timestamp_iso)"
        echo "========================================================================"

        if command -v ollama >/dev/null 2>&1; then
            ollama ps 2>&1 || true
        else
            echo "The ollama command was not found on PATH."
        fi
    } >> "${OLLAMA_PS_LOG}"
}


terminate_r_process() {
    local signal_name="${1:-TERM}"

    if kill -0 "${R_PID}" 2>/dev/null; then
        kill "-${signal_name}" "${R_PID}" 2>/dev/null || true
    fi
}


# ---------------------------------------------------------------------------
# Initialize logs
# ---------------------------------------------------------------------------

OLLAMA_LOG_PATH="$(find_ollama_log)"

cat > "${PROCESS_LOG}" <<'CSV'
timestamp,elapsed_seconds,category,pid,ppid,cpu_percent,rss_mb,elapsed_process_time,command
CSV

cat > "${AGGREGATE_LOG}" <<'CSV'
timestamp,elapsed_seconds,r_process_count,ollama_process_count,total_process_count,r_cpu_percent,ollama_cpu_percent,total_cpu_percent,r_rss_mb,ollama_rss_mb,total_rss_mb,r_console_bytes,r_console_age_seconds,ollama_log_bytes,ollama_log_age_seconds
CSV

cat > "${SYSTEM_LOG}" <<'CSV'
timestamp,elapsed_seconds,total_ram_mb,available_ram_estimate_mb,memory_free_percent,load_average
CSV

{
    echo "Run ID: ${RUN_ID}"
    echo "Started: $(timestamp_iso)"
    echo "Project directory: ${PROJECT_DIR}"
    echo "R script: ${R_SCRIPT}"
    echo "Rscript executable: $(command -v Rscript)"
    echo "Sample interval seconds: ${SAMPLE_INTERVAL}"
    echo "Timeout seconds: ${TIMEOUT_SECONDS}"
    echo "Ollama log path: ${OLLAMA_LOG_PATH:-not found}"
    echo "macOS version: $(sw_vers -productVersion 2>/dev/null || echo unknown)"
    echo "Hardware architecture: $(uname -m)"
    echo "Logical CPUs: $(sysctl -n hw.logicalcpu 2>/dev/null || echo unknown)"
    echo "Physical CPUs: $(sysctl -n hw.physicalcpu 2>/dev/null || echo unknown)"
    echo "Total memory bytes: $(sysctl -n hw.memsize 2>/dev/null || echo unknown)"
    echo "R version:"
    Rscript --version 2>&1 || true
    echo "Ollama version:"

    if command -v ollama >/dev/null 2>&1; then
        ollama --version 2>&1 || true
    else
        echo "ollama command unavailable"
    fi
} > "${RUN_METADATA}"


# ---------------------------------------------------------------------------
# Start R
# ---------------------------------------------------------------------------

echo "Starting R script:"
echo "  ${R_SCRIPT}"
echo ""
echo "Diagnostic directory:"
echo "  ${RUN_DIR}"
echo ""
echo "Sampling interval: ${SAMPLE_INTERVAL} seconds"
echo "Timeout: ${TIMEOUT_SECONDS} seconds"
echo ""

RUN_START_EPOCH="$(date '+%s')"

# `--vanilla` prevents saved workspaces and user startup files from changing
# the run unexpectedly. Remove it only if SampleUser.R intentionally depends
# on a user or project profile.
Rscript --vanilla "${R_SCRIPT}" > "${R_CONSOLE_LOG}" 2>&1 &

R_PID=$!

echo "R process ID: ${R_PID}"
echo ""
echo "Press Ctrl+C to stop this monitoring script and the R run."
echo ""

snapshot_ollama_ps


# ---------------------------------------------------------------------------
# Interrupt handling
# ---------------------------------------------------------------------------

interrupt_run() {
    echo ""
    echo "Interrupt received. Stopping R process ${R_PID}..."

    INTERRUPTED=1

    terminate_r_process TERM
    sleep 2

    if kill -0 "${R_PID}" 2>/dev/null; then
        terminate_r_process KILL
    fi
}

trap interrupt_run INT TERM


# ---------------------------------------------------------------------------
# Monitoring loop
# ---------------------------------------------------------------------------

SAMPLE_NUMBER=0
LAST_R_CONSOLE_SIZE=0
LAST_OLLAMA_LOG_SIZE=0
LAST_PROGRESS_EPOCH="${RUN_START_EPOCH}"

while kill -0 "${R_PID}" 2>/dev/null; do
    NOW_EPOCH="$(date '+%s')"
    ELAPSED_SECONDS=$((NOW_EPOCH - RUN_START_EPOCH))
    SAMPLE_TIMESTAMP="$(timestamp_iso)"

    SAMPLE_NUMBER=$((SAMPLE_NUMBER + 1))

    # Timeout handling.
    if (
        [[ "${TIMEOUT_SECONDS}" -gt 0 ]] &&
        [[ "${ELAPSED_SECONDS}" -ge "${TIMEOUT_SECONDS}" ]]
    ); then
        echo ""
        echo "Timeout reached after ${ELAPSED_SECONDS} seconds."
        echo "Stopping R process ${R_PID}..."

        TIMED_OUT=1

        terminate_r_process TERM
        sleep 3

        if kill -0 "${R_PID}" 2>/dev/null; then
            terminate_r_process KILL
        fi

        break
    fi

    R_PIDS="$(
        collect_descendants "${R_PID}" 2>/dev/null ||
            true
    )"

    OLLAMA_PIDS="$(
        collect_ollama_pids 2>/dev/null ||
            true
    )"

    RELATED_PIDS="$(
        {
            printf '%s\n' "${R_PIDS}"
            printf '%s\n' "${OLLAMA_PIDS}"
        } |
            awk 'NF > 0' |
            sort -n -u
    )"

    R_CPU=0
    OLLAMA_CPU=0
    TOTAL_CPU=0

    R_RSS_KB=0
    OLLAMA_RSS_KB=0
    TOTAL_RSS_KB=0

    R_PROCESS_COUNT=0
    OLLAMA_PROCESS_COUNT=0
    TOTAL_PROCESS_COUNT=0

    for PID in ${RELATED_PIDS}; do
        PROCESS_ROW="$(
            ps -p "${PID}" \
                -o pid=,ppid=,%cpu=,rss=,etime=,comm= \
                2>/dev/null ||
                true
        )"

        if [[ -z "${PROCESS_ROW}" ]]; then
            continue
        fi

        read -r \
            PROCESS_PID \
            PROCESS_PPID \
            PROCESS_CPU \
            PROCESS_RSS_KB \
            PROCESS_ELAPSED \
            PROCESS_COMMAND \
            <<< "${PROCESS_ROW}"

        if [[ -z "${PROCESS_PID:-}" ]]; then
            continue
        fi

        PROCESS_CPU="$(numeric_or_zero "${PROCESS_CPU:-0}")"
        PROCESS_RSS_KB="$(integer_or_zero "${PROCESS_RSS_KB:-0}")"

        CATEGORY="other"
        IS_R_PROCESS=0
        IS_OLLAMA_PROCESS=0

        if pid_in_list "${PROCESS_PID}" "${R_PIDS}"; then
            IS_R_PROCESS=1
        fi

        if pid_in_list "${PROCESS_PID}" "${OLLAMA_PIDS}"; then
            IS_OLLAMA_PROCESS=1
        fi

        # If a process ever appears in both lists, classify it as Ollama to
        # avoid double counting model-runner use as R use.
        if [[ "${IS_OLLAMA_PROCESS}" -eq 1 ]]; then
            CATEGORY="ollama"
            OLLAMA_PROCESS_COUNT=$((OLLAMA_PROCESS_COUNT + 1))
        elif [[ "${IS_R_PROCESS}" -eq 1 ]]; then
            CATEGORY="r"
            R_PROCESS_COUNT=$((R_PROCESS_COUNT + 1))
        fi

        TOTAL_PROCESS_COUNT=$((TOTAL_PROCESS_COUNT + 1))

        TOTAL_CPU="$(
            awk \
                -v a="${TOTAL_CPU}" \
                -v b="${PROCESS_CPU}" '
            BEGIN {
                printf "%.2f", a + b
            }
            '
        )"

        TOTAL_RSS_KB=$((TOTAL_RSS_KB + PROCESS_RSS_KB))

        if [[ "${CATEGORY}" == "r" ]]; then
            R_CPU="$(
                awk \
                    -v a="${R_CPU}" \
                    -v b="${PROCESS_CPU}" '
                BEGIN {
                    printf "%.2f", a + b
                }
                '
            )"

            R_RSS_KB=$((R_RSS_KB + PROCESS_RSS_KB))
        fi

        if [[ "${CATEGORY}" == "ollama" ]]; then
            OLLAMA_CPU="$(
                awk \
                    -v a="${OLLAMA_CPU}" \
                    -v b="${PROCESS_CPU}" '
                BEGIN {
                    printf "%.2f", a + b
                }
                '
            )"

            OLLAMA_RSS_KB=$((OLLAMA_RSS_KB + PROCESS_RSS_KB))
        fi

        PROCESS_RSS_MB="$(
            awk -v kb="${PROCESS_RSS_KB}" '
            BEGIN {
                printf "%.1f", kb / 1024
            }
            '
        )"

        SAFE_COMMAND="$(
            sanitize_csv_text "${PROCESS_COMMAND:-unknown}"
        )"

        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "${SAMPLE_TIMESTAMP}" \
            "${ELAPSED_SECONDS}" \
            "${CATEGORY}" \
            "${PROCESS_PID}" \
            "${PROCESS_PPID}" \
            "${PROCESS_CPU}" \
            "${PROCESS_RSS_MB}" \
            "${PROCESS_ELAPSED:-NA}" \
            "${SAFE_COMMAND}" \
            >> "${PROCESS_LOG}"
    done

    R_RSS_MB="$(
        awk -v kb="${R_RSS_KB}" '
        BEGIN {
            printf "%.1f", kb / 1024
        }
        '
    )"

    OLLAMA_RSS_MB="$(
        awk -v kb="${OLLAMA_RSS_KB}" '
        BEGIN {
            printf "%.1f", kb / 1024
        }
        '
    )"

    TOTAL_RSS_MB="$(
        awk -v kb="${TOTAL_RSS_KB}" '
        BEGIN {
            printf "%.1f", kb / 1024
        }
        '
    )"

    R_CONSOLE_SIZE="$(file_size_bytes "${R_CONSOLE_LOG}")"
    R_CONSOLE_AGE="$(file_age_seconds "${R_CONSOLE_LOG}")"

    if [[ -n "${OLLAMA_LOG_PATH}" ]]; then
        OLLAMA_LOG_SIZE="$(
            file_size_bytes "${OLLAMA_LOG_PATH}"
        )"

        OLLAMA_LOG_AGE="$(
            file_age_seconds "${OLLAMA_LOG_PATH}"
        )"
    else
        OLLAMA_LOG_SIZE=0
        OLLAMA_LOG_AGE=-1
    fi

    # Treat growth in either R output or Ollama logs as observable progress.
    if (
        [[ "${R_CONSOLE_SIZE}" -gt "${LAST_R_CONSOLE_SIZE}" ]] ||
        [[ "${OLLAMA_LOG_SIZE}" -gt "${LAST_OLLAMA_LOG_SIZE}" ]]
    ); then
        LAST_PROGRESS_EPOCH="${NOW_EPOCH}"
    fi

    LAST_R_CONSOLE_SIZE="${R_CONSOLE_SIZE}"
    LAST_OLLAMA_LOG_SIZE="${OLLAMA_LOG_SIZE}"

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "${SAMPLE_TIMESTAMP}" \
        "${ELAPSED_SECONDS}" \
        "${R_PROCESS_COUNT}" \
        "${OLLAMA_PROCESS_COUNT}" \
        "${TOTAL_PROCESS_COUNT}" \
        "${R_CPU}" \
        "${OLLAMA_CPU}" \
        "${TOTAL_CPU}" \
        "${R_RSS_MB}" \
        "${OLLAMA_RSS_MB}" \
        "${TOTAL_RSS_MB}" \
        "${R_CONSOLE_SIZE}" \
        "${R_CONSOLE_AGE}" \
        "${OLLAMA_LOG_SIZE}" \
        "${OLLAMA_LOG_AGE}" \
        >> "${AGGREGATE_LOG}"

    SYSTEM_MEMORY="$(system_memory_sample)"

    SYSTEM_TOTAL_RAM="$(
        printf '%s' "${SYSTEM_MEMORY}" |
            cut -d, -f1
    )"

    SYSTEM_AVAILABLE_RAM="$(
        printf '%s' "${SYSTEM_MEMORY}" |
            cut -d, -f2
    )"

    SYSTEM_FREE_PERCENT="$(
        printf '%s' "${SYSTEM_MEMORY}" |
            cut -d, -f3
    )"

    LOAD_AVERAGE="$(
        sysctl -n vm.loadavg 2>/dev/null |
            tr -d '{},' |
            xargs ||
            echo "NA"
    )"

    printf '%s,%s,%s,%s,%s,"%s"\n' \
        "${SAMPLE_TIMESTAMP}" \
        "${ELAPSED_SECONDS}" \
        "${SYSTEM_TOTAL_RAM}" \
        "${SYSTEM_AVAILABLE_RAM}" \
        "${SYSTEM_FREE_PERCENT}" \
        "${LOAD_AVERAGE}" \
        >> "${SYSTEM_LOG}"

    # `ollama ps` is sampled less frequently because invoking it every
    # interval adds unnecessary overhead.
    if ((SAMPLE_NUMBER % 5 == 0)); then
        snapshot_ollama_ps
    fi

    SECONDS_SINCE_VISIBLE_PROGRESS=$((NOW_EPOCH - LAST_PROGRESS_EPOCH))

    printf '\rElapsed: %5ss | R CPU: %6s%% | Ollama CPU: %6s%% | R RAM: %8s MB | Ollama RAM: %8s MB | No visible log growth: %4ss' \
        "${ELAPSED_SECONDS}" \
        "${R_CPU}" \
        "${OLLAMA_CPU}" \
        "${R_RSS_MB}" \
        "${OLLAMA_RSS_MB}" \
        "${SECONDS_SINCE_VISIBLE_PROGRESS}"

    sleep "${SAMPLE_INTERVAL}"
done

echo ""


# ---------------------------------------------------------------------------
# Obtain R exit status
# ---------------------------------------------------------------------------

wait "${R_PID}"
R_EXIT_STATUS=$?

RUN_END_EPOCH="$(date '+%s')"
TOTAL_DURATION=$((RUN_END_EPOCH - RUN_START_EPOCH))

snapshot_ollama_ps


# ---------------------------------------------------------------------------
# Generate diagnostic report
# ---------------------------------------------------------------------------

AGGREGATE_SUMMARY="$(
    awk -F, '
    NR > 1 {
        sample_count++

        if ($6 + 0 > max_r_cpu) {
            max_r_cpu = $6 + 0
        }

        if ($7 + 0 > max_ollama_cpu) {
            max_ollama_cpu = $7 + 0
        }

        if ($8 + 0 > max_total_cpu) {
            max_total_cpu = $8 + 0
        }

        if ($9 + 0 > max_r_rss) {
            max_r_rss = $9 + 0
        }

        if ($10 + 0 > max_ollama_rss) {
            max_ollama_rss = $10 + 0
        }

        if ($11 + 0 > max_total_rss) {
            max_total_rss = $11 + 0
        }

        final_console_bytes = $12
        final_console_age = $13
        final_ollama_log_bytes = $14
        final_ollama_log_age = $15
    }

    END {
        printf "sample_count=%d\n", sample_count + 0
        printf "max_r_cpu=%.2f\n", max_r_cpu + 0
        printf "max_ollama_cpu=%.2f\n", max_ollama_cpu + 0
        printf "max_total_cpu=%.2f\n", max_total_cpu + 0
        printf "max_r_rss=%.1f\n", max_r_rss + 0
        printf "max_ollama_rss=%.1f\n", max_ollama_rss + 0
        printf "max_total_rss=%.1f\n", max_total_rss + 0
        printf "final_console_bytes=%s\n", final_console_bytes
        printf "final_console_age=%s\n", final_console_age
        printf "final_ollama_log_bytes=%s\n", final_ollama_log_bytes
        printf "final_ollama_log_age=%s\n", final_ollama_log_age
    }
    ' "${AGGREGATE_LOG}"
)"

MIN_AVAILABLE_RAM="$(
    awk -F, '
    NR > 1 && $4 != "" && $4 != "NA" {
        if (!initialized || $4 + 0 < minimum) {
            minimum = $4 + 0
            initialized = 1
        }
    }

    END {
        if (initialized) {
            printf "%.0f", minimum
        } else {
            print "NA"
        }
    }
    ' "${SYSTEM_LOG}"
)"


get_summary_value() {
    local key="$1"

    printf '%s\n' "${AGGREGATE_SUMMARY}" |
        awk -F= -v requested="${key}" '
        $1 == requested {
            print $2
        }
        '
}


MAX_R_CPU="$(get_summary_value max_r_cpu)"
MAX_OLLAMA_CPU="$(get_summary_value max_ollama_cpu)"
MAX_TOTAL_CPU="$(get_summary_value max_total_cpu)"
MAX_R_RSS="$(get_summary_value max_r_rss)"
MAX_OLLAMA_RSS="$(get_summary_value max_ollama_rss)"
MAX_TOTAL_RSS="$(get_summary_value max_total_rss)"
SAMPLE_COUNT="$(get_summary_value sample_count)"
FINAL_CONSOLE_BYTES="$(get_summary_value final_console_bytes)"
FINAL_CONSOLE_AGE="$(get_summary_value final_console_age)"
FINAL_OLLAMA_LOG_BYTES="$(get_summary_value final_ollama_log_bytes)"
FINAL_OLLAMA_LOG_AGE="$(get_summary_value final_ollama_log_age)"

LOG_STALL_SECONDS=$((RUN_END_EPOCH - LAST_PROGRESS_EPOCH))


{
    echo "SampleUser.R performance diagnostic"
    echo "==================================="
    echo ""
    echo "Run information"
    echo "---------------"
    echo "Run ID: ${RUN_ID}"
    echo "Project directory: ${PROJECT_DIR}"
    echo "R script: ${R_SCRIPT}"
    echo "Start time: $(format_epoch_utc "${RUN_START_EPOCH}")"
    echo "End time: $(format_epoch_utc "${RUN_END_EPOCH}")"
    echo "Duration seconds: ${TOTAL_DURATION}"
    echo "R exit status: ${R_EXIT_STATUS}"
    echo "Timed out: ${TIMED_OUT}"
    echo "Interrupted: ${INTERRUPTED}"
    echo "Samples collected: ${SAMPLE_COUNT:-0}"
    echo ""
    echo "Peak related-process utilization"
    echo "--------------------------------"
    echo "Peak R-process CPU percent: ${MAX_R_CPU:-NA}"
    echo "Peak Ollama CPU percent: ${MAX_OLLAMA_CPU:-NA}"
    echo "Peak combined CPU percent: ${MAX_TOTAL_CPU:-NA}"
    echo "Peak R-process RAM MB: ${MAX_R_RSS:-NA}"
    echo "Peak Ollama RAM MB: ${MAX_OLLAMA_RSS:-NA}"
    echo "Peak combined RAM MB: ${MAX_TOTAL_RSS:-NA}"
    echo "Minimum estimated available system RAM MB: ${MIN_AVAILABLE_RAM}"
    echo ""
    echo "Progress indicators"
    echo "-------------------"
    echo "Final R console size bytes: ${FINAL_CONSOLE_BYTES:-0}"
    echo "Final R console age seconds: ${FINAL_CONSOLE_AGE:-NA}"
    echo "Final Ollama log size bytes: ${FINAL_OLLAMA_LOG_BYTES:-0}"
    echo "Final Ollama log age seconds: ${FINAL_OLLAMA_LOG_AGE:-NA}"
    echo "Seconds since last observed R/Ollama log growth: ${LOG_STALL_SECONDS}"
    echo ""
    echo "Important interpretation notes"
    echo "------------------------------"
    echo "- macOS process CPU can exceed 100% when a process uses multiple cores."
    echo "- RSS is resident memory and does not include every form of shared or"
    echo "  GPU memory."
    echo "- Available memory is estimated from free, inactive, and speculative"
    echo "  pages reported by vm_stat."
    echo "- A lack of console or log growth does not prove inference is stalled."
    echo "  ellmer structured requests are synchronous and may remain silent until"
    echo "  the complete structured response has been received."
    echo "- Sustained Ollama CPU activity generally indicates continuing model work."
    echo "- Very high Ollama RAM combined with low available RAM may indicate"
    echo "  memory pressure."
    echo ""
    echo "Automated interpretation"
    echo "------------------------"

    if [[ "${TIMED_OUT}" -eq 1 ]]; then
        echo "- The run exceeded the configured timeout and was terminated."
    elif [[ "${INTERRUPTED}" -eq 1 ]]; then
        echo "- The run was interrupted by the user."
    elif [[ "${R_EXIT_STATUS}" -eq 0 ]]; then
        echo "- The R process completed successfully."
    else
        echo "- The R process ended with a nonzero status. Inspect r_console.log."
    fi

    if awk -v value="${MAX_OLLAMA_CPU:-0}" '
        BEGIN {
            exit !(value >= 25)
        }
        '; then

        echo "- Ollama showed substantial CPU activity during the run."
    else
        echo "- Ollama CPU activity was low. The request may have spent time"
        echo "  loading, waiting, using GPU acceleration, or stalled outside"
        echo "  model generation."
    fi

    if [[ "${MIN_AVAILABLE_RAM}" != "NA" ]]; then
        if awk -v value="${MIN_AVAILABLE_RAM}" '
            BEGIN {
                exit !(value < 1024)
            }
            '; then

            echo "- Estimated available RAM fell below 1 GB. Memory pressure"
            echo "  may have slowed inference substantially."

        elif awk -v value="${MIN_AVAILABLE_RAM}" '
            BEGIN {
                exit !(value < 2048)
            }
            '; then

            echo "- Estimated available RAM fell below 2 GB. Monitor for"
            echo "  memory pressure."
        else
            echo "- Estimated available RAM did not fall below 2 GB."
        fi
    else
        echo "- Available system RAM could not be estimated."
    fi

    if [[ "${LOG_STALL_SECONDS}" -ge 300 ]]; then
        echo "- Neither the R console nor the detected Ollama log grew for at"
        echo "  least five minutes before termination. Compare this with CPU"
        echo "  activity before concluding that the request stalled."
    fi

    echo ""
    echo "Output files"
    echo "------------"
    echo "R console: ${R_CONSOLE_LOG}"
    echo "Per-process samples: ${PROCESS_LOG}"
    echo "Aggregate samples: ${AGGREGATE_LOG}"
    echo "System samples: ${SYSTEM_LOG}"
    echo "Ollama model snapshots: ${OLLAMA_PS_LOG}"
    echo "Run metadata: ${RUN_METADATA}"
    echo ""
    echo "Last 40 lines of the R console"
    echo "------------------------------"
    tail -n 40 "${R_CONSOLE_LOG}" 2>/dev/null || true
    echo ""
    echo "Final ollama ps output"
    echo "----------------------"

    if command -v ollama >/dev/null 2>&1; then
        ollama ps 2>&1 || true
    else
        echo "ollama command unavailable"
    fi

    echo ""
    echo "Detected Ollama log"
    echo "-------------------"
    echo "${OLLAMA_LOG_PATH:-No standard Ollama log detected}"
    echo ""

    if (
        [[ -n "${OLLAMA_LOG_PATH}" ]] &&
        [[ -f "${OLLAMA_LOG_PATH}" ]]
    ); then
        echo "Last 30 lines of the Ollama log"
        echo "-------------------------------"
        tail -n 30 "${OLLAMA_LOG_PATH}" 2>/dev/null || true
    fi
} > "${DIAGNOSTIC_REPORT}"


# ---------------------------------------------------------------------------
# Final console message
# ---------------------------------------------------------------------------

echo ""
echo "Run finished."
echo ""
echo "R exit status: ${R_EXIT_STATUS}"
echo "Duration: ${TOTAL_DURATION} seconds"
echo ""
echo "Diagnostic report:"
echo "  ${DIAGNOSTIC_REPORT}"
echo ""
echo "R console output:"
echo "  ${R_CONSOLE_LOG}"
echo ""

cat "${DIAGNOSTIC_REPORT}"

exit "${R_EXIT_STATUS}"