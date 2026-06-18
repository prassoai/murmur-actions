# Murmur Spawn — composite GitHub Action

Spawn a murmur agent from a GitHub workflow, optionally wait for it to finish,
and read its structured output back into the job — an "agent-powered check run".

A **composite action**: a `run:` step does
`docker run … ghcr.io/prassoai/murmur-cli:main spawn --json …` against the
public murmur CLI image, and a shell step parses the typed `--json` output into
the action's step outputs. The CLI stays format-agnostic; the GitHub-Actions
glue lives here.

## Auth

A service-profile **API key** (`mur_…`) on the `api-key` input (store it as a
secret), sent over gRPC to `murmur-api` (`api-address`, default
`api.murmur.dev:9090`). No OIDC, webhook, or repo token.

## Usage

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      checks: write          # to post the agent's findings — the agent's identity is separate
    steps:
      - uses: actions/checkout@v4
      - id: review
        uses: prassoai/murmur-actions/spawn@v1
        with:
          api-key:   ${{ secrets.MURMUR_API_KEY }}
          workspace: my-workspace
          slug:      "review-${{ github.run_id }}-${{ github.run_attempt }}"
          prompt:    "Review the diff for ${{ github.event.pull_request.html_url }}."
          output-schema: "@.murmur/review-schema.json"   # @ = read from the checkout; inline JSON also accepted
          expected-output: respond
      - env:
          # Bind via env — never interpolate ${{ }} agent output into a script body.
          STRUCTURED_OUTPUT: ${{ steps.review.outputs.structured-output }}
        run: |
          echo "$STRUCTURED_OUTPUT" | jq -c '.findings[]' | while read -r f; do
            : # emit a check-run annotation per finding, using the job's GITHUB_TOKEN
          done
```

## Inputs / outputs

See [`action.yml`](./action.yml). Key inputs: `api-key`, `api-address` (gRPC
host:port, empty = production default), `workspace`, `slug` (required — no silent
default), `prompt`, `output-schema` (inline or `@path` into the checkout),
`expected-output`, `on-idle`, `wait`, `force-new`, `timeout`. Outputs:
`structured-output` (the caller-schema `result` as JSON), `response`, `phase`,
`is-error`, `agent-ref`.

The composite step parses the CLI's `--json` and writes these to
`$GITHUB_OUTPUT`. `agent-ref` is written right after the spawn — before the
wait — so it survives a wait that times out. A waited run whose agent reported
an error (`is-error=true`), or that ended in a failed/canceled phase, fails the
step (after the outputs are written, so an `if: always()` step can still read
`is-error`/`phase`).

By default `on-idle: terminate` — the agent tears itself down once it finishes,
so a CI spawn leaves nothing lingering. Set `on-idle: sleep` to keep it reachable
for follow-ups (see [`queue-add`](../queue-add)), or `keep-alive` for a
long-lived session.

### Persistent worker (fire-and-return)

For a long-lived agent that reports asynchronously (e.g. a per-PR verifier that
posts its own PR comment), set `wait: "false"` (spawn and return immediately;
only `agent-ref` is emitted), `on-idle: sleep` (stay reachable for follow-ups),
and `force-new: "true"` (start clean even if a dead same-slug agent lingers).

## Structured output

When `output-schema` is set, the agent returns a `{response, feedback, result}`
envelope: `result` conforms to your schema and is surfaced verbatim on
`structured-output`; `response` is a human-readable summary. With no schema you
get a plain `response`. The schema is validated server-side at spawn. Supported
on the Claude backend only.
