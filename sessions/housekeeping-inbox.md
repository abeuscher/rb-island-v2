# Housekeeping Inbox

Small items noticed between sessions. One bullet per item, free-form text. When the inbox
accumulates enough items to be worth a session, batch them into a housekeeping session. An
item that grows into "own session" shape gets promoted to its own entry in the plan file
instead.

**How items get here:** capture them mid-session with `logbug "what you noticed"` — it stamps
the item with the date (and the project's VERSION marker, if it has one) and parks it in
`sessions/housekeeping-incoming.md`. The next `/close-session` digests that buffer: each item
is checked against current code, then the survivors fold in here with their capture stamp
intact.

**Verify the premise before scheduling.** A captured item is a snapshot of the project at
capture time; the project moves underneath it. When picking a batch from this inbox, re-check
each candidate against current code first — items are frequently already-fixed or already
addressed by something that landed since capture. Catch that at the walk, not
mid-implementation.

---

## Inbox

*(Items destined for the next housekeeping session.)*

## Recently dispositioned

*(Log of what left the inbox and where it went. Keep the last few batches' worth; trim older
entries once they're no longer useful context.)*

---

## Disposition rules

Each item leaves the inbox one of four ways:

- **Fold** into the next housekeeping session — the default.
- **Merge** into an existing plan-file entry — note it there and cross-reference back here.
- **Promote** to its own plan-file entry.
- **Drop** as no longer relevant — note briefly under "Recently dispositioned," with why.
