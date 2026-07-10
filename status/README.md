# Murmur Status — composite GitHub Action

Read a murmur agent's current state from a GitHub workflow **without
blocking**. A pure read: the step never fails on agent state — a failed,
canceled, or still-running agent is a reported outcome, not a step failure.
Branch on the outputs.

A **composite action**: a `run:` step does
`docker run … ghcr.io/prassoai/murmur-cli:main status --json …` and parses the
typed `AgentStatus` into the action's outputs. The CLI knows nothing about
GitHub Actions; the output glue lives in the action.

## When to use it (instead of `wait`)

- **`if: always()` reporting.** A final step that reads whatever state the
  agent is in — even after an earlier step failed or timed out — and renders a
  job summary or updates a check run.
- **Conditional dispatch.** Check whether a persistent per-PR worker exists
  and is alive before choosing a path.
- **Scheduled sweeps.** A cron workflow that inspects long-lived agents and
  alerts on `PHASE_FAILED`.

Use [`wait`](../wait) when you need to *block* for a result; use `status` when
you need to *observe* without failing the step.

## Missing agents

With `tolerate-missing: "true"` (default), querying a slug that has no record
(never spawned, or already fully torn down) succeeds with `exists=false` and
empty status outputs — only the server's agent-`NotFound` is absorbed; real
transport/auth errors still fail the step. Gate on `exists` before reading the
other outputs. Set `tolerate-missing: "false"` to fail on a missing agent.

## Auth

A service-profile **API key** (`mur_…`) on `api-key` (store it as a secret),
over gRPC to `murmur-api` (`api-address`, default `api.murmur.dev:9090`).

## Usage

```yaml
- id: agent
  if: always()                    # report whatever state the agent ended in
  uses: prassoai/murmur-actions/status@v1
  with:
    api-key:   ${{ secrets.MURMUR_API_KEY }}
    workspace: my-workspace
    slug:      verify-pr-${{ github.event.pull_request.number }}

- if: always() && steps.agent.outputs.exists == 'true'
  env:
    # Bind via env, never interpolate ${{ … }} into the script body: the
    # response is agent-generated text.
    PHASE:    ${{ steps.agent.outputs.phase }}
    RESPONSE: ${{ steps.agent.outputs.response }}
  run: |
    {
      echo "### Verifier agent: $PHASE"
      echo
      echo "$RESPONSE"
    } >>"$GITHUB_STEP_SUMMARY"
```

## Inputs / outputs

See [`action.yml`](./action.yml). Inputs: `api-key`, `api-address`,
`workspace`, `slug`, `tolerate-missing` (default `"true"`). Outputs:
`agent-ref`, `exists`, `phase`, `is-error`, `response`, `structured-output`
(status outputs are empty when `exists` is `"false"`).
