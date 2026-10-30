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
| Workflows | 8 (`perf-01` … `perf-08`) | |
| Runs per workflow | 12 | The CI Panel loads only the latest 12 runs per workflow |
| Jobs per run | 30 (matrix `shard-1` … `shard-30`) | |
| Steps per job | 4: Set up job, Run shard, Upload artifact, Complete job | GitHub adds the first and last |
| Artifacts per job | 1 (`shard-<n>`), `retention-days: 1` | They expire one day after setup, then the repo never changes again |

As the CI Panel loads it: 8 + 96 runs + 2,880 jobs + 11,520 steps ≈
**14,500 tree nodes**, from 1 + 8 + 2·96 = **201 REST requests** per load.

**Outcomes are deterministic.** `perf-01` … `perf-06` always pass.
`perf-07` and `perf-08` always fail `shard-30` (all other shards pass), so
every run of those workflows ends with *failure*. `fail-fast: false` keeps a
failing shard from cancelling the others.

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
2. Create the runs (96 dispatches, about 5 minutes; safe to re-run, since it
   only adds missing runs):
   ```bash
   scripts/dispatch-runs.sh
   ```
3. Wait until all 96 runs have finished. The Free plan runs 20 jobs at a
   time, and each job takes about 20–40 s including runner setup, so the
   2,880 jobs take roughly **1–1.5 hours** (up to about 2 hours if runners
   are slow to pick up jobs). Minutes are free and unlimited for public repos.

   To avoid 24 failure emails (`perf-07`/`perf-08` fail by design), turn off
   email for Actions under **Settings → Notifications → System → Actions**
   for `mw-ci-test` before dispatching.
4. Check the shape (read-only):
   ```bash
   scripts/verify.sh
   ```
   Expected: 8 workflows, each with 12 completed runs, 30 jobs per run and
   4 steps per job. Artifacts read 30 per run until they expire, then 0.

If a run fails for an unexpected reason (e.g. a runner outage), **don't
re-run it**: a re-run adds an attempt and changes the data. Delete the bad
run in the web UI, run `scripts/dispatch-runs.sh` again to replace it, and
check with `scripts/verify.sh`.

## Token for the tests

The perf tests read this repo with a fine-grained PAT owned by
`mw-ci-test`, limited to the perf repos, with **Actions: Read** and
**Metadata: Read** permissions. It's stored in TCWS as
`CIPANEL_PERF_GHA_TOKEN`.
