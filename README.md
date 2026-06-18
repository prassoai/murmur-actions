# murmur-actions

Composite GitHub Actions for [Murmur](https://github.com/prassoai/murmuration) —
drive murmur agents from any GitHub workflow: spawn an agent and read its
structured output back into a job, send follow-ups to a running agent, and tear
it down on a lifecycle event.

> **Canonical source.** This repo *is* the source of these actions. Any GitHub
> repository can consume them directly:
> `uses: prassoai/murmur-actions/<name>@<ref>`. (They used to be generated from
> `prassoai/murmuration/actions/`; that copy is gone — edit them here.)

## How they work

Each action is a **composite action** whose `run:` step does
`docker run … ghcr.io/prassoai/murmur-cli:main <command> … --json` against the
public murmur CLI image, then parses the typed `--json` output to set the
action's step outputs. The CLI itself is format-agnostic — it only emits
`--json`; the GitHub-Actions glue (parsing, `$GITHUB_OUTPUT`, deliver-or-spawn,
idempotent teardown) lives in the composite step. There is no MCP-over-bash
plumbing and no Go toolchain on the runner — just `docker` and `jq`, both
present on `ubuntu-latest`.

The image (`ghcr.io/prassoai/murmur-cli`) is a **public** GHCR package, so the
`docker run` pulls with no auth. The `:main` tag tracks the latest released CLI.

## Auth

Every action authenticates to `murmur-api` with a **service-profile API key**
(`mur_…`), passed as the `api-key` input (store it as a GitHub Actions secret).
The CLI talks gRPC to `murmur-api`; set the endpoint with `api-address`
(host:port, e.g. `api.murmur.dev:9090`) or leave it empty for the production
default. There is no OIDC, webhook, or repo token involved.

## Actions

- [`spawn`](./spawn) — spawn a murmur agent, optionally wait for it, and return
  its structured output as an "agent-powered check run".
- [`queue-add`](./queue-add) — send a follow-up to a running agent
  (`--preempt` for latest-wins re-runs); reports `delivered`.
- [`kill`](./kill) — cancel an agent and its subtree (idempotent teardown).

## Usage

```yaml
- uses: prassoai/murmur-actions/spawn@v1
  with:
    api-key:   ${{ secrets.MURMUR_API_KEY }}
    workspace: my-workspace
    slug:      "review-${{ github.run_id }}-${{ github.run_attempt }}"
    prompt:    "Review the diff for ${{ github.event.pull_request.html_url }}."
    output-schema: "@.murmur/review-schema.json"   # optional; inline JSON also works
```

See each action's `README.md` for full inputs/outputs.

## Versioning / pinning

**Pin to a full commit SHA** — `uses: prassoai/murmur-actions/spawn@<sha>` —
especially for any job that exposes the `MURMUR_API_KEY` secret. A mutable tag
(`@v1`, `@main`) lets a retagged or compromised upstream run attacker-controlled
code in your secret-bearing job and exfiltrate the key; an immutable SHA can't
move under you. Add a trailing `# v1` comment so the human-readable version is
still visible. `@v1` (the moving major tag) is offered for convenience and
non-sensitive use, but SHA-pinning is the recommended default.
