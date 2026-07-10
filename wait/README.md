# Murmur Wait — composite GitHub Action

Block until a murmur agent reaches a target phase — or is terminal/at rest —
and read its result into step outputs. The standalone counterpart of the wait
built into [`spawn`](../spawn): use it to **join an agent this step did not
spawn**.

A **composite action**: a `run:` step does
`docker run … ghcr.io/prassoai/murmur-cli:main wait --json …` and parses the
typed `AgentStatus` into the action's outputs. The CLI knows nothing about
GitHub Actions; the output glue lives in the action.

## When to use it (instead of `spawn`'s built-in wait)

- **Spawn-early / join-late.** Spawn with `wait: "false"` at the top of the
  job, run the rest of CI concurrently with the agent's work, and `wait` at
  the end to collect `structured-output`.
- **Cross-job / cross-workflow joins.** One job (or another workflow, or a
  webhook-triggered flight) starts the agent; a later job waits on the slug
  and consumes the result.
- **Phase gates.** `phase: running` waits until a persistent worker is
  actually up before follow-ups are delivered to it.
- **Timeout recovery.** If a wait times out, a later step or job can simply
  wait again on the same slug — nothing is lost.

## Semantics

Same contract as `spawn`'s wait tail: on a normal wait end the step writes
`phase` / `is-error` / `response` / `structured-output`, then **fails** on an
agent-reported error or a `PHASE_FAILED` / `PHASE_CANCELED` terminal phase —
after the outputs are written, so an `if: always()` consumer still sees them.
For a read that never fails on agent state, use [`status`](../status).

**Timeout.** On a client-deadline expiry the CLI reports the agent's *latest*
status before exiting non-zero, so the step still writes all outputs — with
`timed-out=true` and the latest observed `phase` — and then fails. A
still-running agent has no terminal result: when `timed-out` is `"true"`,
`response`/`structured-output` reflect the last completed turn (if any), not a
final answer.

## Auth

A service-profile **API key** (`mur_…`) on `api-key` (store it as a secret),
over gRPC to `murmur-api` (`api-address`, default `api.murmur.dev:9090`).

## Usage

```yaml
- uses: prassoai/murmur-actions/spawn@v1
  with:
    api-key:   ${{ secrets.MURMUR_API_KEY }}
    workspace: my-workspace
    slug:      "review-${{ github.run_id }}-${{ github.run_attempt }}"
    prompt:    "Review the diff for ${{ github.event.pull_request.html_url }}."
    output-schema: "@.murmur/review-schema.json"
    wait:      "false"            # fire-and-return; join below

- run: make build test            # CI proceeds while the agent works

- id: review
  uses: prassoai/murmur-actions/wait@v1
  with:
    api-key:   ${{ secrets.MURMUR_API_KEY }}
    workspace: my-workspace
    slug:      "review-${{ github.run_id }}-${{ github.run_attempt }}"
    timeout:   "900"
```

## Inputs / outputs

See [`action.yml`](./action.yml). Inputs: `api-key`, `api-address`,
`workspace`, `slug`, `phase` (optional — human or enum spelling, e.g.
`running`, `task-complete`; empty waits until terminal/at rest), `timeout`
(default `"600"` seconds; `"0"` = no client deadline). Outputs: `agent-ref`,
`phase`, `is-error`, `timed-out`, `response`, `structured-output`.
