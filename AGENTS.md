# Agent instructions

Read [`README.md`](README.md) before making changes. It is the source of truth
for the repository layout, operating and recovery model, validation commands,
maintenance conventions, generated documentation, and automation. Follow the
more specific README files linked from it when working in those areas.

## Agent behavior

- Inspect current source, evaluated configuration, and runtime state as
  appropriate; do not treat remembered or generated summaries as authoritative.
- Preserve user-owned working-tree and staged changes. Select only task-scoped
  files or hunks for edits and commits.
- Keep agent-authored design specifications and implementation plans under
  `.agent-work/`. Never commit that directory unless the user explicitly asks.
- Keep secrets out of messages, tool output, patches, commit messages, and
  generated documentation. Report secret names only when useful.
- Make safe, scoped repository changes autonomously. Obtain explicit user
  approval before deployments, reboots, credential mutations, destructive
  operations, force-pushes, or other live-impacting actions.
- Never restart a host while a game is active. Use the check documented in the
  README before any gaming-host restart.
- Validate changes using the commands and proportionality guidance in the
  README, and report what was actually run.

## Agent commit attribution

When Codex materially contributes to a commit, append this trailer after a
blank line so GitHub records the contribution. Do not add it to commits Codex
did not help author.

```text
Co-authored-by: Codex <codex@openai.com>
```
