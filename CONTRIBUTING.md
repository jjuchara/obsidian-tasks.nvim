# Contributing

Issues and focused pull requests are welcome.

## Local setup

Clone the repository and add it to Neovim's runtime path through your plugin manager or `set rtp+=/path/to/obsidian-tasks.nvim`.

## Tests

```sh
nvim --headless -u NONE -i NONE \
  "+set rtp+=$PWD" \
  "+luafile tests/run.lua" \
  +qa
```

Before submitting a change:

1. Add a regression test for behavior changes.
2. Run the headless suite on a supported Neovim version.
3. Run `stylua --check lua plugin tests` when StyLua is available.
4. Update README, help, and changelog when user-facing behavior changes.

Keep modules dependency-free unless a dependency provides a clear benefit that cannot reasonably be implemented with the Neovim API.

## Manual testing with LazyVim

The development launcher loads this working tree in the existing `LazyVim` app profile while redirecting task writes to an isolated resource:

```sh
./scripts/nvim-dev
```

The resource persists at `~/.local/state/obsidian-tasks.nvim-dev/Tasks.md`. Restore it from `tests/fixtures/dev-tasks.md` with `./scripts/nvim-dev --reset-resource`. To use another disposable file, set `OBSIDIAN_TASKS_TASK_FILE=/path/to/Tasks.md`.

The LazyVim plugin spec must select its directory and repository from the launcher environment:

```lua
local dev = vim.env.OBSIDIAN_TASKS_PROFILE == "dev"

{
  "jjuchara/obsidian-tasks.nvim",
  dir = dev and vim.env.OBSIDIAN_TASKS_PLUGIN_DIR or nil,
  opts = {
    repositories = dev and {
      { name = "dev", path = vim.env.OBSIDIAN_TASKS_TASK_FILE },
    } or production_repositories,
  },
}
```

A normal LazyVim launch continues to use the Git checkout and production repositories. Never point the development profile at a production vault when testing write operations.
