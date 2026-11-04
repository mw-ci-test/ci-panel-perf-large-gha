# ci-panel-perf-large-gha

**Frozen** test data for the CI Panel performance tests (MATLAB, UPT). The
tests only *read* this repo. They time how long the CI Panel takes to load
and display a large GitHub Actions project.

**Do not push changes, add triggers, dispatch or re-run workflows** without
coordinating with the CI Panel QE owners. Any new run changes the data the
performance trend is based on.

## Shape

| | Count | Why |
|---|---|---|
| Workflows | 5 (`perf-01` … `perf-05`) | |
| Runs per workflow | 12 | The CI Panel loads only the latest 12 runs per workflow |
| Jobs per run | 15 (matrix `shard-1` … `shard-15`) | |
| Steps per job | 10: Set up job, Check out, Set up MATLAB, Install dependencies, Build, Run tests, Generate test report, Package, Upload artifact, Complete job | Shaped like a MATLAB CI job; the steps only echo. GitHub adds the first and last |
| Artifacts per job | 1 (`shard-<n>`), `retention-days: 1` | They expire one day after setup, then the repo never changes again |

As the CI Panel loads it: 5 + 60 runs + 900 jobs + 9,000 steps ≈
**9,965 tree nodes**, from 1 + 5 + 2·60 = **126 REST requests** per load.
(Resized on 2026-11-03 from 8 × 12 × 30 × 4 steps, which took too long to
load.)

**Outcomes are deterministic.** `perf-01` … `perf-04` always pass.
`perf-05` always fails the "Run tests" step of `shard-15` (all other shards
pass), so every run of `perf-05` ends with *failure*. `fail-fast: false`
keeps a failing shard from cancelling the others, and the steps after "Run
tests" use `if: always()` so every job keeps all 10 steps.

## Why it's built this way

- **`workflow_dispatch` only.** No push, pull request or schedule triggers,
  so nobody can add runs by pushing or opening a PR.
- **Public repo, `ubuntu-latest`.** Standard GitHub-hosted runners are free
  for public repositories. Don't switch the repo to private and don't use
  larger runners: both cost money.
- **1-day artifacts.** Public repos keep artifacts for at most 90 days, so
  they'd disappear eventually anyway. Letting them expire once, right after
  setup, freezes the repo. The panel still makes the same artifact requests
  (they just come back empty), and artifacts aren't tree nodes.

## One-time setup

Prerequisites: [GitHub CLI](https://cli.github.com/) logged in to github.com
as `mw-ci-test` (`gh auth login --hostname github.com`), and `jq`.

1. Push this content to `main`. Workflows must be on the default branch
   before they can be dispatched.
2. Create the runs (60 dispatches, about 3 minutes; safe to re-run, since it
   only adds missing runs):
   ```bash
   scripts/dispatch-runs.sh
   ```
3. Wait until all 60 runs have finished. The Free plan runs 20 jobs at a
   time, and each job takes about 20–40 s including runner setup, so the
   900 jobs take roughly **20–30 minutes** (longer if runners are slow to
   pick up jobs). Minutes are free and unlimited for public repos.

   To avoid 12 failure emails (`perf-05` fails by design), turn off
   email for Actions under **Settings → Notifications → System → Actions**
   for `mw-ci-test` before dispatching.
4. Check the shape (read-only):
   ```bash
   scripts/verify.sh
   ```
   Expected: 5 workflows, each with 12 completed runs, 15 jobs per run and
   10 steps per job. Artifacts read 15 per run until they expire, then 0.

**To rebuild the data from scratch** (e.g. after changing the shape):
delete every run with `scripts/delete-runs.sh` (cancels runs still in
progress, asks before deleting, cannot be undone), push the new workflows,
check that `gh api repos/mw-ci-test/ci-panel-perf-large-gha/actions/workflows`
lists only the current workflows (removed workflow files disappear once their
runs are gone), then run steps 2–4 again.

If a run fails for an unexpected reason (e.g. a runner outage), **don't
re-run it**: a re-run adds an attempt and changes the data. Delete the bad
run in the web UI, run `scripts/dispatch-runs.sh` again to replace it, and
check with `scripts/verify.sh`.

## Token for the tests

The perf tests read this repo with a fine-grained PAT owned by
`mw-ci-test`, limited to the perf repos, with **Actions: Read** and
**Metadata: Read** permissions. It's stored in TCWS as
`CIPANEL_PERF_GHA_TOKEN`.
