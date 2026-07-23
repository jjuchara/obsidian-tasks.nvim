---
name: obsidian-tasks.nvim
description: A native, keyboard-first task view for Obsidian Markdown inside Neovim.
typography:
  editor:
    fontFamily: "inherit"
    fontSize: "inherit"
    fontWeight: "inherit"
    lineHeight: "inherit"
components:
  task-view:
    typography: "{typography.editor}"
  repository-header:
    typography: "{typography.editor}"
  tag-group:
    typography: "{typography.editor}"
  active-filter:
    typography: "{typography.editor}"
---

# Design System: obsidian-tasks.nvim

This file is a concise public design snapshot for contributors. Canonical design rationale and future design work live in the Russian Obsidian project.

## Overview

**Creative North Star: "The Native Task Outline"**

The task view is a compact outline that belongs inside Neovim rather than imitating a standalone task application. Hierarchy, checkboxes, repository labels, and concise status text carry the interface. The user's colorscheme and terminal font remain authoritative.

The system rejects decorative cards, fixed application palettes, mouse-only controls, and custom interaction models that compete with standard Neovim behavior.

**Key Characteristics:**

- Keyboard-first and fully usable through standard Neovim commands.
- Dense but legible hierarchy based on indentation and semantic highlights.
- Theme-native presentation with no hard-coded runtime colors or fonts.
- Persistent context across refreshes, filters, sorting, and repository navigation.

## Colors

Runtime colors are semantic links to the active Neovim colorscheme. The plugin does not prescribe RGB values.

### Primary

- **Repository Title** (`Title`): repository section headings.
- **Tag Identifier** (`Identifier`): tag hierarchy and group labels.
- **Active Filter** (`Special`): the current filter indicator.

### Neutral

- **Task Text** (`Normal`): active task content.
- **Completed Task** (`Comment`): visually receded completed content.
- **Empty State** (`Comment`): secondary explanatory text.

### Semantic

- **Overdue** (`DiagnosticError`): incomplete tasks past their due date.
- **Due Soon** (`DiagnosticWarn`): incomplete tasks due today or tomorrow.
- **Repository Tabs** (`TabLine`, `TabLineSel`): inactive and active repository tabs.

**The Theme Ownership Rule.** Runtime highlight groups link to standard Neovim groups by default. Users and colorschemes may override them; features must not require a fixed palette.

## Typography

**Display Font:** the user's terminal/editor font
**Body Font:** the user's terminal/editor font
**Label/Mono Font:** the user's terminal/editor font

**Character:** Monospaced, compact, and inherited. Hierarchy comes from content, indentation, and highlight roles rather than font substitution or oversized labels.

### Hierarchy

- **Title:** repository headers and the floating-window title.
- **Body:** task text and checkbox state.
- **Label:** tags, filters, tabs, and concise empty/error states.

**The Editor Typography Rule.** Never set a font family or size from plugin runtime code. Respect the typography selected by the user for Neovim.

## Elevation

The interface is flat by default. A floating view may use the configured native Neovim border; window views use the user's existing layout. Hierarchy is conveyed through indentation, folds, highlights, cursorline, and the winbar, not shadows.

**The Native Surface Rule.** Use Neovim windows and borders as structural boundaries. Do not emulate cards, shadows, blur, or layered web surfaces.

## Components

### Task View

- **Structure:** a scratch buffer rendered as a tag tree with task rows.
- **State:** `cursorline` identifies the active row; the buffer remains non-modifiable.
- **Behavior:** task actions use buffer-local mappings, while standard Neovim navigation remains available.

### Repository Navigation

- **Sections:** repository names appear as highlighted headings when repositories share a view.
- **Tabs:** the winbar uses `TabLine` and `TabLineSel`; keyboard and mouse activation are equivalent.
- **Collected sources:** one repository may render tasks from many Markdown files while preserving each task's physical source for every mutation and navigation action.

### Tag Groups

- **Structure:** indentation communicates tag depth.
- **State:** `▾` marks an expanded group and `▸` marks a collapsed group.
- **Behavior:** native Neovim folds support standard fold commands and fold-column mouse interaction.

### Task Rows

- **Structure:** `[ ]` and `[x]` communicate completion independently of color.
- **State:** due-soon, overdue, completed, and normal tasks use semantic highlight groups.
- **Behavior:** create, toggle, edit, delete, undo, and source-opening actions operate within the current task-view context.

### Inputs and Pickers

- **Style:** use `vim.ui.input` and `vim.ui.select` so the user's configured provider owns presentation.
- **State:** prompts state the expected value and preserve the active view, repository, focus, and selection context when asynchronous providers are used.

## Do's and Don'ts

### Do:

- **Do** preserve standard Neovim behavior for windows, folds, navigation, and highlighting.
- **Do** communicate state with text or symbols in addition to semantic color.
- **Do** keep rendered lines concise and keep Markdown as the only persisted source of truth.
- **Do** preserve cursor, filters, repository selection, and fold state when refreshing a valid view.

### Don't:

- **Don't** build a web dashboard transplanted into a terminal, with cards, decorative chrome, or mouse-first controls.
- **Don't** create a replacement task database that obscures or takes ownership of the underlying Markdown.
- **Don't** add clever custom interactions that conflict with established Neovim motions, folds, windows, and highlight conventions.
- **Don't** add dense status decoration that competes with task text instead of clarifying urgency and completion.
- **Don't** hard-code runtime colors, font families, or font sizes.
