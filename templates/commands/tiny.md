---
description: Capture a lightweight "tiny spec" for quick fixes or bug patches without spinning up a net-new feature branch.
handoffs:
  - label: Update Main Spec
    agent: speckit.update
    prompt: Merge this tiny spec back into spec.md/plan.md when ready
scripts:
  sh: scripts/bash/create-tiny-spec.sh --json "{ARGS}"
  ps: scripts/powershell/create-tiny-spec.ps1 -Json "{ARGS}"
---

## User Input

```text
$ARGUMENTS
```

Use this command when you need to document a narrowly scoped tweak (bugfix, guard-rail adjustment, copy change) within an existing feature. Keep the tiny spec concise (<1 page) and link it back to the parent feature.

## Execution Flow

1. **Run the script** `{SCRIPT}`. It returns JSON containing:
   - `TINY_SPEC` – absolute path to the new file
   - `SLUG` – slug used in `tiny-specs/`
   - `FEATURE_DIR`, `BRANCH` – context for cross-linking

2. **Populate the file** referenced by `TINY_SPEC` using `templates/tiny-spec-template.md` structure:
   - `Context` – what part of the product is impacted? what is broken/missing?
   - `Change Summary` – bullets describing the minimal adjustment
   - `Requirements` – checkboxes that must pass before shipping
   - `Validation` – which manual/automated checks prove success
   - `Impact / Follow-up` – note whether the main spec/plan/tasks need updates later

3. **Link back to the parent artifacts:**
   - In `spec.md`, add a short note (e.g., under Assumptions or a "Tiny Specs" appendix) referencing `tiny-specs/<slug>.md`.
   - If the change affects the technical plan, add a bullet in `plan.md`'s relevant phase pointing to the tiny spec.
   - If implementation work is required, append a short task list in `tiny-specs/<slug>.md` and/or mention which `/speckit.tasks` items should be updated next.

4. **Scope discipline:**
   - If the change grows beyond a handful of requirements, recommend switching to `/speckit.update` or `/speckit.specify --update-current` so the primary spec stays authoritative.
   - Tiny specs should never replace the full spec/plan—they are additive, single-purpose notes.

5. **Completion report:**
   - Confirm the file path, summarize the requirements/validation you captured, and state whether a follow-up `/speckit.update`, `/speckit.plan`, or `/speckit.tasks` run is needed to merge the tiny spec back into the main artifacts.
