# murmur-actions

Composite GitHub Actions for [Murmur](https://github.com/prassoai/murmuration) —
spawn agents from CI and read their structured output back into a job.

> **Canonical source.** These actions are published here from
> `prassoai/murmuration/actions/<name>`. Edit them there, not in this repo.

## Actions

- [`spawn`](./spawn) — spawn a murmur agent, wait for it, and return its
  structured output as an "agent-powered check run". Authenticates with a
  service-profile API key (`mur_…`) over murmur-api's `/mcp` endpoint.

  ```yaml
  - uses: prassoai/murmur-actions/spawn@v1
    with:
      api-url:   ${{ vars.MURMUR_API_URL }}
      api-key:   ${{ secrets.MURMUR_API_KEY }}
      workspace: murmuration
      prompt:    "Review the diff for ${{ github.event.pull_request.html_url }}."
  ```

  See [`spawn/README.md`](./spawn/README.md) for full inputs/outputs.
