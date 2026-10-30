#!/usr/bin/env bash
# Creates the frozen test data: dispatches every workflow until it has
# RUNS_PER_WORKFLOW runs. Re-runnable: workflows that already have enough
# runs are skipped, so this never pushes a workflow past the target.
#
# Prerequisite (once):  gh auth login --hostname github.com   (as mw-ci-test)
# Usage:                scripts/dispatch-runs.sh

set -euo pipefail

REPO="${REPO:-mw-ci-test/ci-panel-perf-large-gha}"
RUNS_PER_WORKFLOW="${RUNS_PER_WORKFLOW:-12}"
WORKFLOWS=(perf-01.yml perf-02.yml perf-03.yml perf-04.yml perf-05.yml perf-06.yml perf-07.yml perf-08.yml)
export GH_HOST=github.com

run_count() {
    gh api "repos/$REPO/actions/workflows/$1/runs?per_page=1" --jq '.total_count'
}

declare -A missing
total=0
for wf in "${WORKFLOWS[@]}"; do
    have=$(run_count "$wf")
    need=$(( RUNS_PER_WORKFLOW - have ))
    (( need < 0 )) && need=0
    missing[$wf]=$need
    total=$(( total + need ))
    echo "$wf: $have run(s), dispatching $need"
done

if (( total == 0 )); then
    echo "Nothing to do."
    exit 0
fi

read -r -p "Dispatch $total run(s) to $REPO? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Cancelled."; exit 1; }

# Round-robin so all workflows progress together. The pause keeps us well
# under GitHub's limit of 80 content-creating requests per minute.
for (( round = 1; round <= RUNS_PER_WORKFLOW; round++ )); do
    for wf in "${WORKFLOWS[@]}"; do
        if (( missing[$wf] > 0 )); then
            gh workflow run "$wf" -R "$REPO" --ref main
            missing[$wf]=$(( missing[$wf] - 1 ))
            echo "dispatched $wf (round $round)"
            sleep 3
        fi
    done
done

echo "Done. Wait for all runs to finish, then run scripts/verify.sh."
