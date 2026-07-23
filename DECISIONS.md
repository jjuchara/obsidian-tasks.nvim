# Decisions

This release-facing log summarizes durable product and architecture constraints for contributors. The canonical decision history, product direction, and design live in the Russian Obsidian project; implementation details that do not constrain public behavior do not belong here.

## D-001: Markdown files remain the only source of truth

- **Status:** Accepted
- **Decision:** Read and mutate ordinary Markdown task files directly. Do not introduce a plugin-owned task database or hidden synchronization layer.
- **Consequences:** Every write must remain understandable outside Neovim. Persistence work must preserve user data, detect stale task lines, and fail explicitly when a safe update is not possible.

## D-002: Core runtime stays dependency-free

- **Status:** Accepted
- **Decision:** Implement the core workflow with built-in Neovim APIs. Optional integrations may improve presentation or discovery, but core commands and task operations must not require them.
- **Consequences:** Inputs use `vim.ui.input` and `vim.ui.select`, views use native buffers and windows, and grouping uses native folds. Optional UI providers must preserve the same behavior.

## D-003: Repository tabs live inside one task view

- **Status:** Accepted
- **Decision:** `view.repository_mode = "tabs"` renders repository tabs inside the task view instead of creating Neovim tabpages.
- **Consequences:** Switching repositories keeps one plugin window and must preserve the active filter, fold state, and cursor context whenever possible.

## D-004: Task mutations are guarded and undoable

- **Status:** Accepted
- **Decision:** Locate a task from its original source line before changing it, write through a temporary file and atomic rename, and retain one-step undo state for the latest successful create, toggle, edit, or delete operation.
- **Consequences:** External edits that make a task missing or ambiguous stop the mutation and require a refresh. Undo also refuses to overwrite unexpected external changes.

## D-005: Public docs ship in English and mirror into second brain in Russian

- **Status:** Superseded by D-007
- **Decision:** `README.md`, Vim help, roadmap, changelog, contribution guidance, and this decision log are maintained with the code in English. Complete Russian translations are maintained in the `obsidian task` second-brain project.
- **Consequences:** This symmetric mirror model was replaced when the Obsidian project became the single source of truth and repository documentation was narrowed to code-adjacent and release-facing projections.

## D-006: Collected sources remain directly mutable

- **Status:** Accepted
- **Decision:** A logical repository may aggregate Markdown tasks through ordered source globs. Every collected task retains its physical source path and line, while computed source and project tags exist only in the view.
- **Consequences:** Create always writes to the repository task file; toggle, edit, delete, source opening, and undo target the collected task's original file. Computed tags participate in grouping and filtering but never leak into Markdown edits or creation tag pickers. Overlapping source globs are deterministic: the first match owns the file.

## D-007: Obsidian owns canonical project knowledge

- **Status:** Accepted
- **Decision:** Maintain product thinking, planning, ideas, decisions, design, manual-testing evidence, and roadmap state in Russian under the Obsidian `obsidian task` project. Keep this Git repository limited to code-adjacent and release-facing English documentation required by users and contributors.
- **Consequences:** Repository README, Vim help, changelog, contributor guidance, roadmap, product/design, and decision files are public projections rather than the authority for project direction. Meaningful work updates Obsidian first and then refreshes every affected public projection; repository-only planning is not durable project state.
