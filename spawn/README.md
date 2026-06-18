# Murmur Spawn — composite GitHub Action

Spawn a murmur agent from a GitHub workflow, wait for it to finish, and read its
structured output back into the job — an "agent-powered check run".

This directory is the **canonical source**. It is published to the public
`prassoai/murmur-actions` repo (referenced as `prassoai/murmur-actions/spawn@v1`)
by release tooling; consumers never reference the private monorepo directly.

## Auth

The action calls the **existing** `murmur-api` Spawn path with a service-profile
**API key** (`mur_…`) sent as `Authorization: Bearer …` to the `/mcp`
Streamable-HTTP endpoint. Store the key as a GitHub Actions secret. There is no
OIDC, webhook, or repo token involved — that path is for *reactive* webhook
event ingestion; this action is *imperative*. See
[`docs/finished/DESIGN_GHA_SPAWN_ACTION.md`](../../docs/finished/DESIGN_GHA_SPAWN_ACTION.md).

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
          api-url:   ${{ vars.MURMUR_API_URL }}
          api-key:   ${{ secrets.MURMUR_API_KEY }}
          workspace: murmuration
          prompt: "Review the diff for ${{ github.event.pull_request.html_url }}."
          output-schema: "@.murmur/review-schema.json"   # @ = read from file; inline JSON also accepted
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

See [`action.yml`](./action.yml). Key inputs: `api-url`, `api-key`, `workspace`,
`prompt`, `output-schema` (inline or `@path`), `timeout`. Key outputs:
`structured-output` (the caller-schema `result` as JSON), `response`, `phase`,
`is-error`, `agent-ref`.

## Structured output

When `output-schema` is set, the agent returns a `{response, feedback, result}`
envelope: `result` conforms to your schema and is surfaced verbatim on
`structured-output`; `response` is a human-readable summary. With no schema you
get a plain `response`. The schema is validated server-side at spawn (a
malformed schema fails the spawn). Supported on the Claude backend only.
