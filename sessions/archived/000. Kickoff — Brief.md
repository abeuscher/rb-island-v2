# Session 000 — Kickoff — Brief

**Type:** planning
**Shape:** stub-driven
**Branch:** <this session's branch, per `branch-pattern` in `sessions/config.md`>

## Goal

Turn `sessions/proposal.md` into the plan file — the first set of entries this project will
actually work through session by session.

## Reading list

Read these before doing anything else, in order:

1. `sessions/proposal.md` — what the project is meant to become. If it doesn't exist yet,
   say so and stop; session-init scaffolded this brief expecting it to be written first.
2. The plan file (its skeleton, scaffolded empty by session-init).
3. `sessions/config.md` — the project's session types and other settings.

## Plan

- Read the proposal in full before drafting anything.
- Break it into entries in the plan file: each one scoped, sequenced, and given a success
  criterion and an artifact, per the plan file's own "How this doc is used" section.
- Split anything that looks too big for one session's context into more than one entry
  rather than writing an oversized entry.
- Flag anything in the proposal that's ambiguous or that you'd need a real decision on before
  it can become an entry — list these as open questions rather than guessing silently, since
  this session sets the shape everything downstream inherits.
- Don't start building anything from the plan yet. This session's artifact is the plan file
  itself, filled in — not the first entry's work.

## Out of scope

Implementing any entry the plan produces. That starts at the next session.

## Open questions

Surfaced during planning, once the proposal has been read. Omit if none.

---

## Process rules

Follow the `session-protocol` skill's process rules. Planning sessions get the model
reserved for planning work (see the skill's model-choice note), not the project's default.

This session is the likeliest place internal-handle language leaks into what the user reads
— the proposal itself usually has its own vocabulary (milestone or phase codes, section
numbers), and it's tempting to carry that straight into the orientation. Don't: follow the
project's `CLAUDE.md` and describe the plan by what it builds, not by the codes it's keyed to.

## Session Open Gate

After reading the list above, post a short orientation — what the proposal covers, the shape
of the plan you're about to draft — in the project's language, not the proposal's own
section/milestone vocabulary. Wait for confirmation before drafting entries.

## Session Close Gate

Everything below happens only when the user runs `/close-session`. See the `session-protocol`
skill for the full Close Gate steps; this brief adds no session-specific steps beyond those.
