---
description: Refine existing specs, plans, or task lists in-place without creating a new feature branch.
handoffs:
  - label: Re-run Plan
    agent: speckit.plan
    prompt: Replan the feature with the following deltas after /speckit.update
  - label: Re-run Tasks
    agent: speckit.tasks
    prompt: Regenerate the task list after these spec/plan adjustments
scripts:
  sh: scripts/bash/update-feature.sh --json "{ARGS}"
  ps: scripts/powershell/update-feature.ps1 -Json "{ARGS}"
---

## User Input

```text
$ARGUMENTS
```

The text typed after `/speckit.update` captures the requested deltas (new requirements, bugfix scope, clarifications, etc.). It may also include optional flags:

- `--targets spec|plan|tasks|all` – control which artifacts to edit (default: spec)
- `--clarify-only` – collect answers/clarifications without modifying artifacts yet
- `--skip-checklists` – acknowledge that checklists will be revisited later
- `--no-backup` – skip `.bak` snapshots (script reports when this occurs)

## Execution Flow

1. **Run the script** `{SCRIPT}` (arguments already handled). Parse the JSON payload:
   - `FEATURE_DIR`, `BRANCH` – where to edit
   - `TARGETS` – list of artifacts to touch (subset of `spec|plan|tasks`)
   - `FILES.<target>` – absolute file paths
   - `BACKUPS` – `.bak` files created before editing (may be empty if `--no-backup`)
   - `CLARIFY_ONLY` / `SKIP_CHECKLISTS` booleans

2. **If `CLARIFY_ONLY=true`:**
   - Do not modify the artifacts yet.
   - Extract every question/unknown from the user input.
   - Append a new "Clarifications – {date}" block near the top of `spec.md` summarising the open questions and any answers provided.
   - Exit after returning the list of questions plus guidance on which command to run after answers arrive (usually `/speckit.update` again without `--clarify-only`).

3. **For each requested target:**
   - **spec** – Load the existing structure, highlight the sections being updated, and rewrite only the affected paragraphs. Preserve numbering/anchors. Include a short `### Change Log – {date}` note (or append to an existing "Change Log" section) referencing why the spec moved.
   - **plan** – Update the affected sections in `plan.md` and any derivative files (`research.md`, `data-model.md`, `contracts/`, `quickstart.md`). Call out downstream actions (e.g., "Phase 1 contract X now includes ...").
   - **tasks** – Ensure every requirement introduced/updated above is reflected in `tasks.md`. Mark removed tasks as struck-through with rationale and add replacements.

4. **Checklists & quality gates:**
   - If `SKIP_CHECKLISTS=false`, re-open the relevant checklist (e.g., `checklists/requirements.md`) and tick/retick items, calling out any newly failed criteria.
   - If `SKIP_CHECKLISTS=true`, explicitly warn the user that checklist updates were deferred.

5. **Cross-artifact alignment:**
   - Reference `BACKUPS` to communicate what changed ("diff against ...bak...").
   - Update `research.md` or `tiny-specs/` with decision notes when appropriate so future `/speckit.plan` runs have context.

6. **Report completion:**
   - Summarize which files were edited, which checklists were refreshed/deferred, and any required follow-up commands (`/speckit.plan`, `/speckit.tasks`, `/speckit.analyze`).
   - If tasks or plan now lag spec, explicitly recommend the next slash command to get them back in sync.

## Additional Guidance

- Never create or rename branches inside `/speckit.update`—all edits stay on the current branch.
- If a requested artifact is missing (e.g., user targeted `plan` before running `/speckit.plan`), stop with a clear error directing them to the correct command.
- For larger rewrites, consider recommending a dedicated `/speckit.specify --update-current` run followed by `/speckit.plan`/`/speckit.tasks`.
