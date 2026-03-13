---
tracker:
  kind: linear
  project_slug: "regatta-cli-55a669bdb3c9"
  active_states:
    - Todo
    - In Progress
    - Merging
    - Rework
  terminal_states:
    - Closed
    - Cancelled
    - Canceled
    - Duplicate
    - Done
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-workspaces
hooks:
  after_create: |
    git clone --depth 1 https://github.com/dzmbs/regatta.git .
agent:
  max_concurrent_agents: 5
  max_turns: 20
agent_runtime:
  backend: pi
pi:
  command: pi
  model: anthropic/claude-sonnet-4-5
  thinking: high
---

You are working on a Linear ticket `{{ issue.identifier }}`

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the ticket is still in an active state.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless needed for new code changes.
- Do not end the turn while the issue remains in an active state unless you are blocked by missing required permissions/secrets.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This is an unattended orchestration session. Never ask a human to perform follow-up actions.
2. Only stop early for a true blocker (missing required auth/permissions/secrets). If blocked, record it in the workpad and move the issue according to workflow.
3. Final message must report completed actions and blockers only. Do not include "next steps for user".

Work only in the provided repository copy. Do not touch any other path.

## Project context

This is `regatta-cli`, a Zig SDK and CLI for Pacifica (crypto trading platform).

- Build: `zig build`
- Test: `zig build test`
- Architecture: `src/lib/` (primitives), `src/sdk/` (protocol), `src/cli/` (commands)
- Pipe-aware output, semantic exit codes, agent-friendly design
- See `AGENTS.md` for full coding conventions

## Prerequisite: Linear MCP or `linear_graphql` tool is available

The agent should be able to talk to Linear, either via a configured Linear MCP server or injected `linear_graphql` tool. If none are present, stop and ask the user to configure Linear.

## Default posture

- Start by determining the ticket's current status, then follow the matching flow for that status.
- Start every task by opening the tracking workpad comment and bringing it up to date before doing new implementation work.
- Spend extra effort up front on planning and verification design before implementation.
- Reproduce first: always confirm the current behavior/issue signal before changing code so the fix target is explicit.
- Keep ticket metadata current (state, checklist, acceptance criteria, links).
- Use a single persistent Linear comment as the source of truth for progress.
- Run `zig build test` before any commit or push.

## Related skills

- `linear`: interact with Linear.
- `commit`: produce clean, logical commits during implementation.
- `push`: keep remote branch current and publish updates.
- `pull`: keep branch updated with latest `origin/main` before handoff.
- `land`: when ticket reaches `Merging`, follow the `land` skill.

## Status map

- `Backlog` -> out of scope; do not modify.
- `Todo` -> immediately transition to `In Progress` before active work.
- `In Progress` -> implementation actively underway.
- `Human Review` -> PR is attached and validated; waiting on human approval.
- `Merging` -> approved by human; execute the `land` skill flow.
- `Rework` -> reviewer requested changes; planning + implementation required.
- `Done` -> terminal state; no further action required.
