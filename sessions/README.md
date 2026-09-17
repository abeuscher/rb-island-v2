# Sessions

This project uses the `session-kit` plugin's session protocol (`/open-session`,
`/close-session`). The protocol itself — brief shapes, session types, the gates, the
housekeeping flow — lives in the plugin's `session-protocol` skill, not here; this file just
orients you to what's in this folder.

- `config.md` — this project's settings (plan file, branch pattern, verify step, test
  command, archive-after, enabled session types).
- `plan.md` — the plan: entries, their status, success criteria.
- `NNN. <Title> — Brief.md` / `— Log.md` — each session's brief and log.
- `housekeeping-inbox.md` / `housekeeping-incoming.md` — small items noticed between
  sessions; capture one with `logbug "…"`, digested into the inbox at close.
- `archived/` — briefs and logs older than `archive-after` sessions, moved out but kept in
  git.
- `proposal.md` — write this yourself before the first session; the kickoff brief
  (`000. Kickoff — Brief.md`) turns it into the plan file.

Noticed a rule here that should really live in the protocol itself? Don't edit it into this
project — append it to `sessions/kit-feedback.md` instead, so it can be picked up in
`session-kit` for every project, not just this one.
