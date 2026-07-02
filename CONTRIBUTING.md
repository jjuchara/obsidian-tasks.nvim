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
