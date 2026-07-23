# Murmur Kill — composite GitHub Action

Cancel a murmur agent (and its subtree) from a GitHub workflow. Use it to tear
down a persistent agent on a lifecycle event — e.g. killing a per-PR verifier
when the PR closes.

A **composite action**: a `run:` step does
`docker run … ghcr.io/prassoai/murmur-cli:main kill --json …`. The CLI knows
nothing about GitHub Actions; the idempotent-teardown glue lives in the action.

## Idempotent teardown

The server's `Kill` already tolerates an already-terminal workflow. With
`tolerate-missing: "true"` (default) the action additionally treats a kill of a
slug that was **never spawned** (e.g. a PR opened before the workflow existed) as
success — the shell step absorbs only the `NotFound` an agent with no catalog
record returns. Real transport/auth errors still fail the step. Set
`tolerate-missing: "false"` to fail on any kill error.

## Auth

A service-profile **API key** (`mur_…`) on `api-key` (store it as a secret),
over gRPC to `murmur-api` (`api-address`, default `api.murmur.dev:9090`).

## Usage

```yaml
- uses: prassoai/murmur-actions/kill@v1
  with:
    api-key:   ${{ secrets.MURMUR_API_KEY }}
    workspace: my-workspace
    slug:      verify-${{ github.event.repository.id }}-pr-${{ github.event.pull_request.number }}
```

## Inputs

See [`action.yml`](./action.yml). Inputs: `api-key`, `api-address`, `workspace`,
`slug`, `tolerate-missing` (default `"true"`). No outputs.
