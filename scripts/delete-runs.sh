#!/usr/bin/env bash
# Deletes ALL workflow runs (and their logs and artifacts) in the repo, so
# the test data can be rebuilt from scratch with scripts/dispatch-runs.sh.
# Runs that are still in progress are cancelled first. This cannot be undone.
#
# Prerequisite (once):  gh auth login --hostname github.com   (as mw-ci-test)
# Usage:                scripts/delete-runs.sh

set -euo pipefail

REPO="${REPO:-mw-ci-test/ci-panel-perf-large-gha}"
export GH_HOST=github.com

ids=$(gh api --paginate "repos/$REPO/actions/runs?per_page=100" --jq '.workflow_runs[].id')
count=$(wc -w <<<"$ids")
if (( count == 0 )); then
    echo "No runs to delete."
    exit 0
fi

read -r -p "Delete all $count run(s) in $REPO? This cannot be undone. [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Cancelled."; exit 1; }

# A run must be finished before it can be deleted.
in_progress=$(gh api --paginate "repos/$REPO/actions/runs?per_page=100" \
    --jq '.workflow_runs[] | select(.status != "completed") | .id')
for id in $in_progress; do
    gh run cancel "$id" -R "$REPO" || true
done
if [[ -n "$in_progress" ]]; then
    echo "Waiting 30 s for cancelled runs to finish..."
    sleep 30
fi

# The pause keeps us well under GitHub's limit of 80 content-changing requests per minute.
deleted=0
for id in $ids; do
    gh api -X DELETE "repos/$REPO/actions/runs/$id" --silent
    deleted=$(( deleted + 1 ))
    echo "deleted run $id ($deleted/$count)"
    sleep 1
done

echo "Done. Workflows whose files were removed disappear from the list once all their runs are gone."
