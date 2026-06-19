# Murmur Queue Add — composite GitHub Action

Send a follow-up to a **running** murmur agent from a GitHub workflow. A thin
RPC: it enqueues the message and returns — it does not wait for the agent to
act. Use it to drive a persistent agent (e.g. a per-PR verifier) from CI events.

A **composite action**: a `run:` step does
`docker run … ghcr.io/prassoai/murmur-cli:main queue add --json …` and reports
the outcome (`delivered`) as a step output. The CLI knows nothing about GitHub
Actions; the deliver-or-spawn glue lives in the action's shell step.

## Preempt — latest-wins

With `preempt: "true"` the single `murmur queue add --preempt` call is atomic:
it (1) interrupts the agent's in-flight turn, (2) drops any pending follow-ups,
then (3) enqueues this one. That is the right primitive for "a newer commit
superseded the verification in flight" — one call abandons the stale run and
starts the new one, not a racy `interrupt` + `clear` + `add`.

## Auth

A service-profile **API key** (`mur_…`) on `api-key` (store it as a secret),
over gRPC to `murmur-api` (`api-address`, default `api.murmur.dev:9090`).

## Usage

```yaml
- uses: prassoai/murmur-actions/queue-add@v1
  with:
    api-key:   ${{ secrets.MURMUR_API_KEY }}
    workspace: my-workspace
    slug:      verify-pr-${{ github.event.pull_request.number }}
    preempt:   "true"
    prompt:    "Head is now ${{ github.event.pull_request.head.sha }}; re-verify the new head."
```

## Not-running: fail loud, or hand off to a spawn

By default `queue add` errors when the agent is not running (terminal or
never-spawned) and the step fails. Set `tolerate-not-running: "true"` to turn
that one case into a reported outcome: the step succeeds and sets
`delivered=false` so the caller can spawn a fresh agent. Only the server's
not-running `NotFound` is absorbed — every other error (auth, transport, invalid
argument) still fails the step.

```yaml
- id: deliver
  uses: prassoai/murmur-actions/queue-add@v1
  with:
    # …
    preempt: "true"
    tolerate-not-running: "true"
- if: steps.deliver.outputs.delivered == 'false'
  uses: prassoai/murmur-actions/spawn@v1   # recover: no live agent, spawn one
  with: { … }
```

## Inputs / outputs

See [`action.yml`](./action.yml). Inputs: `api-key`, `api-address`, `workspace`,
`slug`, `prompt`, `preempt` (default `"false"`), `agent-persona` (optional),
`tolerate-not-running` (default `"false"`). Outputs: `agent-ref`, `delivered`
(`"true"` enqueued, `"false"` agent not running and tolerated).
