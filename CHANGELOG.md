# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

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

[Unreleased]: https://github.com/jjuchara/obsidian-tasks.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/jjuchara/obsidian-tasks.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jjuchara/obsidian-tasks.nvim/releases/tag/v0.1.0
