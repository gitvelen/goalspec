# Goal scope & splitting — one goal vs several

When a change is large, should it be one goal or several? This reference gives
the decision criteria. It is for the intake/compile stage (framing the goal)
and for humans deciding scope.

## Premise: a goal is an atomic delivery unit

Once a goal is frozen, **all required criteria must fresh-pass** before
`/goalspec close` succeeds. `### Workunit:` headings in `goal.md` are
**readability and traceability groupings only** — they are not execution units,
do not sequence work, and cannot be closed independently.
`minimum_acceptable_result` only guides drafting one "floor" criterion; it does
**not** enable tiered closure. So a frozen goal **cannot be partially
delivered**. "Should I split?" is really "should these pieces be delivered and
verified separately?"

The only in-goal "chunking" that exists is at the **verification** layer: each
criterion gets its own verdict (per-criterion evidence + `judge apply`), and all
required must pass to close. The **implementation** layer is not chunked by the
framework — the Master drives by criterion and is not forced to advance block by
block (see `loop-driving.md`).

## The per-goal fixed tax (paid once per goal, cannot be amortized)

- 5 human confirmations (goal / intake-package / contract approval + intake
  review / contract review apply).
- 2 fresh-context AI reviews (intake + contract).
- The full intake pass (clarification + drafting capture / constraint
  suggestions). Intake artifacts are **vacated on close and not reused across
  goals**.
- compile / freeze / close verification (final verification + smoke + secret
  scan).

## What is shared across goals (not redone when splitting)

`project/constraints.yaml` / `memory.yaml` / `regression-suite.yaml` are
inherited/accumulated across all goals. Long-term constraints (design
contracts, mapping rules, prohibitions) written into `project_constraints` are
honored by every goal automatically. When a prior goal closes, its regressions
land in `regression-suite.yaml` and are injected into later goals as
`required_evidence` — prior work is guarded.

## What is redone when splitting (the tax)

intake, `goal_constraints`, and the compile/review/freeze/close pass — each
goal pays the fixed tax once.

## Criteria: split vs combine

| Dimension | Signal to split | Signal to combine |
|---|---|---|
| Coupling | pieces are independent, no strong dependency | tightly coupled, two faces of one user value |
| Verification nature | mixed (mechanical grep/DOM **and** subjective screenshot/judgment) | homogeneous (all mechanical, or all judgment) |
| criteria count vs cap | approaching `profile.run_loop.max_iterations` | far below cap |
| Blast radius | one piece stalling should not block the others | mutual blocking is acceptable |
| Dependency direction | a "foundation layer" depended on by many pieces | no foundation layer |

Any one dimension showing a split signal warrants serious consideration;
several at once almost always means split.

> Note: do **not** make "deliver in batches / realize value early" the dominant
> criterion. Goalspec targets AI-implemented projects where AI throughput is
> high and early-delivery value is limited. The dominant criteria are
> **coupling, verification nature, and criteria count** — because they drive
> human-review burden (superlinear), contract-gaps probability, and AI
> attention dilution, none of which AI speed fixes, and all of which land on the
> most expensive resource: human review.

## Granularity guidance

One goal ≈ **one independently statable user value + a homogeneous verification
method + criteria inside the safe band**.

- Safe band: roughly **10–30 required criteria**.
  - Under ~5: consider combining (the fixed tax dominates).
  - Approaching `max_iterations`: seriously consider splitting (cap pressure +
    contract complexity).
- `optional_criteria` don't count (they don't block close): put nice-to-haves
  here and keep them in the same goal without polluting the required set.

## Generic anti-pattern: an oversized mixed goal

Stuffing "mechanically-stoppable residue cleanup + design-system contract and
component foundation + subjective visual overhaul of heavy pages + a narrow
backend cut + acceptance-tooling setup" into **one** goal trips several split
signals at once:

- Mixed verification nature (the first pieces are grep/DOM/unit-test
  machine-judgeable; the visual piece is screenshot human-judgment) → machine
  and judgment criteria in one contract, expensive Master verdict switching,
  messy evidence paths.
- Foundation dependency (the component foundation is consumed by many pages) →
  the foundation can't be closed early, so downstream cannot safely consume it.
- Large blast radius (a visual stall blocks a residue-cleanup that could have
  closed early).
- High criteria count (easily dozens, approaching or exceeding cap).

Ideal split (by "user value + verification nature"):
1. **Foundation goal**: contract + components + tokens + mapping layer.
   Mechanically verifiable, highly reusable, depended on downstream. Close
   early → `project_constraints` anchors the contract → later goals inherit it
   + regression guards it.
2. **Stop-bleeding goal**: residue and internal-id cleanup. Mechanical,
   independent, few criteria, fast.
3. **Narrow backend goal** (if any): independent, can close early.
4. **Visual/subjective goal(s)**: judgment-heavy, split further by page or
   module; each run-loop is small, screenshot verification is homogeneous.

Cost: each of N goals pays the fixed tax once. Gain: foundation stabilizes
early, stop-bleeding delivers early, visuals don't block stop-bleeding, each
contract is simple and judgeable, prior regressions guard later work. **Gain
exceeds tax.**

## In-goal organization tools (correct usage)

- **`### Workunit: <name>`** in `goal.md`: groups Success Model fields for
  readability and traceability **only**. It does not sequence work and is not
  independently deliverable. Use it to organize a large goal's narrative, but
  do not expect it to substitute for splitting.
- **`optional_criteria`**: place nice-to-haves that don't block close; keep them
  in the same goal to absorb edge demands.
- **`minimum_acceptable_result`**: draft one "floor" criterion (below it =
  incomplete); it does **not** enable tiered closure — close still requires all
  required to pass.

## Escape hatches when scope is wrong

- **`goalspec scope amend --allow <glob> --reason <why>`**: when implementation
  legitimately needs to touch new paths **without changing Goal/Criteria/semantic
  Constraints** — only widens `allowed_paths`, does not demote the contract, no
  re-review.
- **`/goalspec reopen <reason>`**: when the **Goal/Criteria/Constraints
  themselves are wrong/insufficient/contradictory**, or a new human acceptance
  bar changes what "done" means — demotes the contract back to draft; requires
  re-review / re-approve / re-freeze. Higher cost than scope amend.

## Why "make the framework focus a big goal internally" is not an alternative

One might propose: instead of splitting, have the framework focus a big goal
internally (narrow the prompt to un-passed criteria / inject trajectory / farm
out work to subagents by workunit). **This does not hold up:**

- The dilution source in a big goal is **task coupling** (one change must
  respect many related points), not prompt length. A frozen prompt with dozens
  of criteria is typically single-digit percent of context — far below the
  attention-decay region.
- Narrowing the prompt to "un-passed criteria" hides already-passed constraints
  from the Master, amplifying reward hacking (passing the current criterion by
  breaking already-passed ones), and breaks freeze reproducibility (the same
  frozen goal yields a different prompt on each run).
- The root fix is **reducing coupling per freeze unit** (splitting), not patching
  focus onto an already-frozen big contract.

## Conclusion

Most large changes spanning **multiple user values / multiple verification
natures** should be split, at 10–30 required criteria per goal, with foundation
work closed first. Do not force one oversized goal to "save the fixed tax" —
that saves intake tax but adds superlinear human-review burden, contract gaps,
AI dilution, and cap risk. And do not expect "internal focus" to substitute for
splitting — it treats symptoms, has side effects, and does not address coupling.
