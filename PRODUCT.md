# Product

This file is a concise public product snapshot for contributors. Canonical product thinking and planning live in the Russian Obsidian project.

## Register

product

## Users

Neovim users who keep tasks in one or more Obsidian vaults and want to review, create, organize, and complete them without leaving the editor. They are comfortable with keyboard-driven workflows and expect Markdown files to remain readable and portable outside the plugin.

## Product Purpose

obsidian-tasks.nvim provides a focused task cockpit over ordinary Markdown checkbox files. It succeeds when common task operations are fast inside Neovim, the source files remain the sole source of truth, and users can adopt the plugin without a database, service, plugin manager integration, or runtime dependency.

## Brand Personality

Native, focused, dependable. The interface should feel like a well-behaved Neovim feature: compact enough for daily use, explicit about state, and quiet when no intervention is required.

## Anti-references

- A web dashboard transplanted into a terminal, with cards, decorative chrome, or mouse-first controls.
- A replacement task database that obscures or takes ownership of the underlying Markdown.
- Clever custom interactions that conflict with established Neovim motions, folds, windows, and highlight conventions.
- Dense status decoration that competes with task text instead of clarifying urgency and completion.

## Design Principles

1. Keep Markdown authoritative. Every mutation must be understandable and safe at the file level.
2. Use Neovim-native affordances. Standard windows, folds, mappings, highlights, and pickers should work as users expect.
3. Keep the task in focus. Navigation and state indicators support task text rather than competing with it.
4. Make state resilient. Refreshes and external file changes should preserve user context whenever the identity of that context remains valid.
5. Add complexity only when it removes repeated work from the core task workflow.

## Accessibility & Inclusion

All core task-view operations must be available from the keyboard. Meaning must not depend on color alone: checkbox markers, labels, fold markers, and text identify state alongside highlights. The plugin inherits the user's Neovim colorscheme and terminal typography, allowing users to retain their chosen contrast and font settings. Motion is not required for comprehension or interaction.
