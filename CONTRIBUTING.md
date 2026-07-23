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
3. Run `stylua --check lua plugin tests`.
4. Regenerate help tags with `nvim --headless -u NONE -i NONE "+helptags doc" +qa` when Vim help tags change.
5. Run `git diff --check`.
6. Update affected canonical project documents in the Russian Obsidian project, then review the English README, Vim help, roadmap snapshot, changelog, and decision snapshot for user-visible drift.

Install StyLua with `brew install stylua` on macOS or use another installation method from the upstream documentation.
Run `stylua lua plugin tests` to format the Lua sources. The project configuration targets LuaJIT and is shared with CI.

Keep modules dependency-free unless a dependency provides a clear benefit that cannot reasonably be implemented with the Neovim API.

Durable product and architecture choices belong in the canonical Russian `DECISIONS.md` inside the `obsidian task` second-brain project referenced from [AGENTS.md](AGENTS.md). The repository [DECISIONS.md](DECISIONS.md) is its concise release-facing projection.

## Manual testing with LazyVim

The development launcher loads this working tree in the existing `LazyVim` app profile while redirecting task writes to an isolated resource:

```sh
./scripts/nvim-dev
```

The resource persists at `~/.local/state/obsidian-tasks.nvim-dev/Tasks.md`. Start with an empty task list by running
`./scripts/nvim-dev --reset`, or load the repository's sample tasks with `./scripts/nvim-dev --fixture`. The previous
`--reset-resource` flag remains available as an alias for `--reset`. To use another disposable file, set
`OBSIDIAN_TASKS_TASK_FILE=/path/to/Tasks.md`.

Keep the LazyVim plugin spec production-only:

```lua
{
  "jjuchara/obsidian-tasks.nvim",
  opts = {
    repositories = production_repositories,
  },
}
```

The launcher starts Neovim in the repository root. Lazy.nvim then loads the project-local `.lazy.lua`, which replaces the
plugin directory and repositories for that process. This relies on lazy.nvim's `local_spec` option, which is enabled by
default. On first launch, inspect `.lazy.lua` when prompted and run `:trust`; Neovim stores trust for the current file
contents. A normal launch outside the development profile continues to use the installed plugin and production
repositories. Never point the development profile at a production vault when testing write operations.
