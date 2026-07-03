# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

## [0.2.2] - 2026-07-03

### Changed

- Moved LazyVim development overrides into a project-local spec so user configuration remains production-only.
- Kept development task writes isolated from production repositories.

### Fixed

- Task creation now continues after entering a new primary tag with asynchronous UI providers.

## [0.2.1] - 2026-07-03

### Added

- Optional repository aliases for user-facing labels.
- Keyboard and mouse navigation between repository tabs.

### Changed

- Repository tab mode now renders inside a single task view instead of creating Neovim tabpages.
- Each repository tab displays only tasks from its selected repository.

## [0.2.0] - 2026-07-03

### Added

- Strict date validation with `today` and `tomorrow` input aliases.
- Date input in the configured display format and the `yesterday` alias.
- Date input without leading zeroes for numeric months and days.
- Configurable display formatting for creation, start, due, and completion dates.
- Source, deadline, and title sorting through `:ObsidianTasksSort` and the task view.
- Virtual overdue, due-soon, and on-track groups for deadline sorting.
- Highlights for due-soon and overdue tasks.

### Changed

- Consolidated all project documentation in English.
- Task refreshes preserve the task under the cursor when possible.

## [0.1.0] - 2026-07-02

### Added

- Multi-repository task loading.
- Floating and native window views.
- Repository sections and tabpage modes.
- Ordered, recursive tag grouping.
- Task completion with completion dates.
- Guided task creation with multiple tags.
- Active, completed, and combined status filters.
- Atomic writes and stale-line protection.
- English, Russian, and `:help` documentation.

[Unreleased]: https://github.com/jjuchara/obsidian-tasks.nvim/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/jjuchara/obsidian-tasks.nvim/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/jjuchara/obsidian-tasks.nvim/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/jjuchara/obsidian-tasks.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jjuchara/obsidian-tasks.nvim/releases/tag/v0.1.0
