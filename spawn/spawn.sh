#!/usr/bin/env bash
# Entrypoint for the Murmur Spawn composite action. Drives three existing hosted
# MCP tools over murmur-api's /mcp Streamable-HTTP endpoint, authenticated with a
# service-profile API key (mur_…) as a Bearer token:
#
#   spawn  → start the agent (owned by the key's service profile)
#   wait   → block until the agent is terminal or at rest
#   status → read AgentStatus, including output.structuredOutput
#
# No OIDC, no webhook, no repo token — see docs/finished/DESIGN_GHA_SPAWN_ACTION.md.
set -euo pipefail

: "${MURMUR_API_URL:?api-url is required}"
: "${MURMUR_API_KEY:?api-key is required}"
: "${MURMUR_WORKSPACE:?workspace is required}"
: "${MURMUR_PROMPT:?prompt is required}"

mcp_url="${MURMUR_API_URL%/}/mcp"
slug="${MURMUR_SLUG:-gha-${MURMUR_RUN_ID:-0}-${MURMUR_RUN_ATTEMPT:-1}}"

# mcp_call NAME ARGUMENTS_JSON → echoes the tool's result text. The /mcp endpoint
# is stateless per POST, so a tools/call needs no initialize handshake. Fails the
# step on a transport error, a JSON-RPC error, or a tool isError result — never
# silently.
mcp_call() {
  local name="$1" arguments="$2"
  local body resp
  body=$(jq -nc --arg name "$name" --argjson arguments "$arguments" \
    '{jsonrpc:"2.0",id:1,method:"tools/call",params:{name:$name,arguments:$arguments}}')

  resp=$(curl -fsS -X POST "$mcp_url" \
    -H "Authorization: Bearer ${MURMUR_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$body") || {
    echo "::error::murmur $name call failed (transport/HTTP error against $mcp_url)" >&2
    exit 1
  }

  if jq -e '.error' >/dev/null 2>&1 <<<"$resp"; then
    echo "::error::murmur $name JSON-RPC error: $(jq -c '.error' <<<"$resp")" >&2
    exit 1
  fi
  if [ "$(jq -r '.result.isError // false' <<<"$resp")" = "true" ]; then
    echo "::error::murmur $name tool error: $(jq -r '.result.content[0].text // "unknown"' <<<"$resp")" >&2
    exit 1
  fi
  jq -r '.result.content[0].text // ""' <<<"$resp"
}

# Resolve the output schema: @path reads a file, anything else is inline.
output_schema="${MURMUR_OUTPUT_SCHEMA:-}"
case "$output_schema" in
  @*)
    schema_path="${output_schema#@}"
    output_schema=$(cat "$schema_path")
    ;;
esac

# Build the spawn arguments, including only the optional fields that are set.
spawn_args=$(jq -nc \
  --arg slug "$slug" \
  --arg description "$MURMUR_PROMPT" \
  --arg workspace "$MURMUR_WORKSPACE" \
  '{slug:$slug, description:$description, workspace:$workspace}')

add_arg() { # KEY VALUE — append a string field only when non-empty
  # if/fi (not `&& … || true`) so an empty value is skipped while a real jq
  # failure still trips set -e instead of silently emptying spawn_args.
  if [ -n "$2" ]; then
    spawn_args=$(jq -c --arg k "$1" --arg v "$2" '. + {($k):$v}' <<<"$spawn_args")
  fi
}
add_arg agent "${MURMUR_CODING_AGENT:-}"
add_arg out "${MURMUR_EXPECTED_OUTPUT:-}"
add_arg model "${MURMUR_MODEL:-}"
add_arg reasoning_effort "${MURMUR_REASONING_EFFORT:-}"
add_arg purpose "${MURMUR_PURPOSE:-}"
add_arg output_schema "$output_schema"
# CI spawns are one-shot: default to tearing the agent down when it goes idle so
# each run leaves nothing lingering. Override via the action's on-idle input.
add_arg on_idle "${MURMUR_ON_IDLE:-terminate}"

echo "Spawning murmur agent '$slug' in workspace '$MURMUR_WORKSPACE'…"
spawn_result=$(mcp_call spawn "$spawn_args")
# The hosted spawn tool returns {"slug":..., "dashboard_url":...}.
echo "$spawn_result"

# /mcp is stateless per POST, so the spawn-time workspace is NOT remembered:
# wait and status must each carry it, or they resolve an AgentId with an empty
# workspace and target the wrong (or no) agent.
echo "Waiting for '$slug' (timeout ${MURMUR_TIMEOUT:-600}s)…"
wait_args=$(jq -nc --arg slug "$slug" --arg workspace "$MURMUR_WORKSPACE" --argjson t "${MURMUR_TIMEOUT:-600}" \
  '{slug:$slug, workspace:$workspace, timeout_seconds:$t}')
mcp_call wait "$wait_args" >/dev/null

status_json=$(mcp_call status "$(jq -nc --arg slug "$slug" --arg workspace "$MURMUR_WORKSPACE" '{slug:$slug, workspace:$workspace}')")

# status returns the AgentStatus proto as protojson (camelCase keys).
phase=$(jq -r '.phase // ""' <<<"$status_json")
response=$(jq -r '.output.response // ""' <<<"$status_json")
is_error=$(jq -r '.output.isError // false' <<<"$status_json")
# structuredOutput is a JSON document held as a string; emit it verbatim ("" when absent).
structured=$(jq -r '.output.structuredOutput // ""' <<<"$status_json")

# Gate BEFORE writing any outputs: the hosted `wait` tool returns the latest
# status (not an MCP error) when it hits timeout_seconds, so a still-running
# phase here means the deadline elapsed and the run never completed. Fail the
# step and write NO outputs — otherwise an `if: always()` consumer could read
# in-progress/partial agent data as if the run had finished. Terminal
# (COMPLETED/FAILED/CANCELED) and at-rest (TASK_COMPLETE/IDLE/SLEEPING) phases
# are the legitimate completed states.
case "$phase" in
  PHASE_TASK_COMPLETE | PHASE_IDLE | PHASE_SLEEPING | PHASE_COMPLETED | PHASE_FAILED | PHASE_CANCELED) ;;
  *)
    echo "::error::murmur agent '$slug' did not reach a terminal or at-rest state within ${MURMUR_TIMEOUT:-600}s (phase=$phase)" >&2
    exit 1
    ;;
esac

# The run completed (possibly with is_error=true). Write outputs now: at this
# point response/structured-output/phase/is-error all reflect a finished turn,
# so they are accurate diagnostics for downstream steps — including an
# `if: always()` step that wants to act on is-error=true.
emit_multiline() {
  local name="$1" value="$2" delim
  delim="ghadelim_$(openssl rand -hex 16)"
  {
    echo "${name}<<${delim}"
    # printf, not echo: a value starting with -n/-e/-E would be eaten as an
    # echo flag and silently dropped.
    printf '%s\n' "$value"
    echo "$delim"
  } >>"$GITHUB_OUTPUT"
}

{
  echo "agent-ref=$slug"
  echo "phase=$phase"
  echo "is-error=$is_error"
} >>"$GITHUB_OUTPUT"
emit_multiline response "$response"
emit_multiline structured-output "$structured"

echo "Agent '$slug' finished in phase '$phase' (is_error=$is_error)."

if [ "$is_error" = "true" ]; then
  echo "::error::murmur agent '$slug' reported an error result" >&2
  exit 1
fi
