#!/usr/bin/env bash
# Checks that the repo matches the frozen shape the CI Panel perf tests expect.
# Read-only. Prints one line per workflow and exits non-zero on any mismatch.
#
# Usage: scripts/verify.sh

set -uo pipefail

REPO="${REPO:-mw-ci-test/ci-panel-perf-large-gha}"
export GH_HOST=github.com

EXPECTED_WORKFLOWS=5
EXPECTED_RUNS=12        # the CI Panel loads only the latest 12 runs per workflow
EXPECTED_JOBS=15
EXPECTED_STEPS=10       # Set up job, 8 workflow steps, Complete job

status=0
fail() { echo "  MISMATCH: $*"; status=1; }

workflows=$(gh api "repos/$REPO/actions/workflows" --jq '.total_count')
echo "workflows: $workflows (expected $EXPECTED_WORKFLOWS)"
(( workflows == EXPECTED_WORKFLOWS )) || fail "workflow count"

for wf in perf-01.yml perf-02.yml perf-03.yml perf-04.yml perf-05.yml; do
    runs_json=$(gh api "repos/$REPO/actions/workflows/$wf/runs?per_page=$EXPECTED_RUNS")
    total=$(jq '.total_count' <<<"$runs_json")
    not_done=$(jq '[.workflow_runs[] | select(.status != "completed")] | length' <<<"$runs_json")
    conclusions=$(jq -r '[.workflow_runs[].conclusion] | group_by(.) | map("\(.[0])=\(length)") | join(",")' <<<"$runs_json")
    latest=$(jq -r '.workflow_runs[0].id' <<<"$runs_json")

    jobs_json=$(gh api "repos/$REPO/actions/runs/$latest/jobs?per_page=100")
    jobs=$(jq '.total_count' <<<"$jobs_json")
    bad_steps=$(jq "[.jobs[] | select((.steps | length) != $EXPECTED_STEPS)] | length" <<<"$jobs_json")
    artifacts=$(gh api "repos/$REPO/actions/runs/$latest/artifacts" --jq '.total_count')

    echo "$wf: runs=$total ($conclusions) latest-run jobs=$jobs artifacts=$artifacts"
    (( total == EXPECTED_RUNS )) || fail "$wf has $total runs, expected $EXPECTED_RUNS"
    (( not_done == 0 ))          || fail "$wf has $not_done run(s) not completed yet"
    (( jobs == EXPECTED_JOBS ))  || fail "$wf latest run has $jobs jobs, expected $EXPECTED_JOBS"
    (( bad_steps == 0 ))         || fail "$wf latest run has $bad_steps job(s) without $EXPECTED_STEPS steps"
done

if (( status == 0 )); then
    echo "OK: repo matches the expected shape."
fi
echo "Artifacts expire 1 day after upload (retention-days: 1); 0 artifacts after that is expected."
exit $status
