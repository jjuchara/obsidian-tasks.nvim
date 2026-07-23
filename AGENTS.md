# Repository Guidelines

## Project Knowledge

- **The single source of truth for project knowledge is always the Russian documentation in Obsidian:** [obsidian task](</Users/jjuchara/Library/Mobile Documents/iCloud~md~obsidian/Documents/obsidian_jjuchara/1. Projects/obsidian task/00. obsidian task.md>). Open it with [obsidian task](obsidian://open?vault=obsidian_jjuchara&file=1.%20Projects%2Fobsidian%20task%2F00.%20obsidian%20task). Product thinking, planning, ideas, decisions, design, manual-testing evidence, and roadmap state live and are maintained there.
- **This Git repository keeps only code-adjacent and release-facing documentation required by plugin users and contributors:** README, Vim help, CHANGELOG, CONTRIBUTING, LICENSE, and concise public snapshots of roadmap and architectural constraints. Repository-facing text stays in English; do not make the repository the canonical home for private project planning.
- **Read `00. obsidian task.md` and the relevant files under `1. Projects/obsidian task/` before planning substantial work.** Use the repository's README, Vim help, and config defaults to verify the shipped public behavior, not to infer uncommitted product direction.
- After meaningful code or behavior changes, update the affected Obsidian source-of-truth documents in Russian first, then refresh affected release-facing repository documents in English when the change is user-visible.
- Record durable product and architecture choices in the Obsidian `DECISIONS.md`; keep the repository `DECISIONS.md` as its concise release-facing projection instead of leaving decisions only in chat, commits, or implementation details.

## Current State

The latest stable release is `v0.8.0`. The plugin targets Neovim 0.10+, has no required runtime dependencies, and supports multi-repository views, source-glob collection with view-only PARA and project tags, ordered tag grouping and filtering, sorting, native folds, guided creation, guarded task mutations, and one-step undo. Treat `README.md`, `doc/obsidian-tasks.txt`, and the defaults in `lua/obsidian-tasks/config.lua` as the public behavior contract, and the Obsidian project as the authority for roadmap and project state.

## Project Structure & Module Organization

Runtime code lives in `lua/obsidian-tasks/`. Keep responsibilities separated by the existing modules: `parser.lua` reads Markdown tasks, `repository.lua` handles file persistence, `grouping.lua` builds tag trees, `ui.lua` renders and controls views, and `config.lua` owns defaults and validation. `init.lua` is the public Lua API. Neovim commands are registered in `plugin/obsidian-tasks.lua`.

Tests are in `tests/run.lua`. User documentation is split between `README.md` and the Vim help file `doc/obsidian-tasks.txt`; update `doc/tags` with `:helptags doc`. Visual assets belong in `assets/`. `FUTURE.md` and `DECISIONS.md` are public snapshots; canonical roadmap and decisions live in Obsidian. Release history remains in `CHANGELOG.md`.

## Build, Test, and Development Commands

This plugin has no build step or required third-party dependencies. Run the complete test suite with:

```sh
nvim --headless -u NONE -i NONE \
  "+set rtp+=$PWD" \
  "+luafile tests/run.lua" \
  +qa
```

Run `stylua --check lua plugin tests` to verify formatting, and `stylua lua plugin tests` to apply it. Validate help tags with `nvim --headless -u NONE -i NONE "+helptags doc" +qa`.

## Coding Style & Naming Conventions

Use Lua with two-space indentation, Unix line endings, and a 120-column limit, as configured in `stylua.toml`. Prefer double quotes where StyLua permits. Name modules and files in lowercase; use `snake_case` for local functions, variables, and configuration keys. Keep the public surface in `require("obsidian-tasks")` small, and prefer built-in Neovim APIs over new dependencies.

## Testing Guidelines

Tests use plain Lua assertions inside a headless Neovim process. Add focused regression coverage to `tests/run.lua` for every behavior change. Use temporary files through `vim.fn.tempname()` and clean them up. Exercise parsing, persistence, and UI entry points without relying on a user configuration or plugin manager.

## Commit & Pull Request Guidelines

History follows Conventional Commit prefixes such as `feat:`, `docs:`, and `ci:`. Write imperative, scoped summaries and keep commits focused. Pull requests should explain the behavior and rationale, link relevant issues, and list verification commands. Include screenshots for visible UI changes. Update the README, Vim help, and changelog when user-facing behavior changes.

## Change Discipline

After every code or documentation change, review the canonical Obsidian project state first, then check `README.md`, `doc/obsidian-tasks.txt`, `FUTURE.md`, `CHANGELOG.md`, and `DECISIONS.md` for affected public projections. Update Obsidian whenever the change alters project state, planning, design, manual evidence, or a durable decision; update repository documents when behavior visible to users or contributors changes. Regenerate `doc/tags` whenever Vim help tags change. Do not describe Obsidian documents as mirrors of the repository.
