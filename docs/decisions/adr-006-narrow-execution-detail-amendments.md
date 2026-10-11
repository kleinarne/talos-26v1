# 6. Allow narrow execution-detail amendments to accepted ADRs

Date: 2026-10-11

## Status

Accepted — supersedes ADR-000.

## Context

ADR-000 made accepted ADRs strictly immutable: any change required supersession by a new ADR. On 2026-10-10, ADR-004 exposed the friction case: after acceptance and before purchase, one execution detail changed (replacement mainboard: ASRock B550 Pro4 → used ASRock Rack X470D4U). The change was made in place as a dated, signed "Amendment" section with preserved original text and rationale — an owner-approved deviation from ADR-000's rule.

Supersession remains the right mechanism for substance changes: the full record of what was decided, why, and what replaced it is the value of the ADR series. But superseding an entire accepted ADR to record a one-part execution change produces ceremony without additional protected history — the dated amendment section carries the same auditable trail (date, rationale, before/after).

## Decision

ADR-000 is superseded. The ADR process for this repo is ADR-000's rules restated verbatim, with the immutability rule extended by one narrowly defined amendment class:

- Format: Nygard (Title, Status, Context, Decision, Consequences) — same
  format as the PKM vault's ADR process, for consistency across projects.
- Location: `docs/decisions/` in the authoritative infrastructure repo.
- Numbering: three digits, strictly increasing, never reused — matching the
  PKM vault's ADR numbering for consistency.
- Lifecycle: Proposed → Accepted → (Deprecated | Superseded).
- Immutability (revised): accepted ADRs are never edited in place, with two
  exceptions:
  1. Typo fixes.
  2. **Execution-detail amendments**: a dated `Amendment (YYYY-MM-DD)`
     section may be appended below the original text, changing only
     implementation/execution details (part choices, versions, names,
     paths). The original text is preserved verbatim; superseded values
     may be marked inline as "superseded — see Amendment" but never
     removed. An amendment never changes the decision's substance, its
     status, or its consequences beyond the detail changed.
- Any substance change still goes through supersession: write a new ADR
  and mark the old one **Superseded by ADR-XXXX**. Never edit or delete
  history outside the exceptions above.
- Changes to this process ADR itself also go through supersession.

ADR-004's existing amendment (2026-10-10, mainboard change) is recorded here as an owner-approved deviation under ADR-000; it satisfies the amendment class introduced by this ADR, and ADR-004 requires no rewrite.

## Consequences

- Execution-detail changes (hardware swaps, version bumps, renames) get a
  lightweight, auditable change path with the same evidence quality as
  supersession: date, rationale, before/after.
- The boundary between execution detail and substance requires judgment.
  Rule of thumb: if the amendment would change what the decision *says*,
  not just which part executes it, it must be a supersession. When
  uncertain, supersede — supersession is always valid.
- The amendment class is the potential erosion path; reviewers (human or
  AI actor) should challenge amendments that drift toward substance.
- ADR numbers are effectively claimed at merge to main: a Proposed ADR-005
  (GitOps single write path) already sits on the
  `docs/adr-005-gitops-write-path` branch (PR #132), which is why this ADR
  takes 006. Draft ADRs on branches must expect renumbering if a
  lower-numbered ADR merges first.
- ADR-000 remains readable as the historical record of the original rule;
  its Status now points here. The PKM vault's ADR-000 is to be superseded
  by an equivalent process ADR through the vault's own branch-and-review
  pipeline, restoring consistency between both series.
