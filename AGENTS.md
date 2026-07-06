# Repository Guidelines

## Project Structure & Module Organization

Runtime code lives in `lua/obsidian-tasks/`. Keep responsibilities separated by the existing modules: `parser.lua` reads Markdown tasks, `repository.lua` handles file persistence, `grouping.lua` builds tag trees, `ui.lua` renders and controls views, and `config.lua` owns defaults and validation. `init.lua` is the public Lua API. Neovim commands are registered in `plugin/obsidian-tasks.lua`.

Tests are in `tests/run.lua`. User documentation is split between `README.md` and the Vim help file `doc/obsidian-tasks.txt`; update `doc/tags` with `:helptags doc`. Visual assets belong in `assets/`, while future scope and release history live in `FUTURE.md` and `CHANGELOG.md`.

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

After every code or documentation change, review `FUTURE.md` and `CHANGELOG.md` for accuracy. Update them whenever the change completes, alters, or supersedes roadmap scope, or introduces user-visible behavior.
