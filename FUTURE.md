# Roadmap

This document tracks ideas that are intentionally outside the current core release. Items are not ordered commitments and may change as the plugin evolves.

## Reliability and compatibility

- Add optimistic locking based on file modification time and content hashes instead of relying only on the original task line.
- Preserve source line endings and the presence or absence of a trailing newline.
- Support nested Markdown tasks and additional checkbox states used by Obsidian Tasks.
- Make date and marker syntax configurable instead of relying on fixed emoji.
- Validate and normalize dates during task creation.
- Add coverage for iCloud conflicts, missing files, and read-only vaults.

## Views and navigation

- Collapse tag groups with native folds.
- Sort tasks by deadline, creation date, title, or repository.
- Filter by tag, repository, and date range.
- Highlight overdue tasks and tasks due today.
- Preserve the cursor, active filter, and expanded groups after refresh.
- Preview the surrounding Markdown source.
- Explore optional Snacks picker and Telescope integrations.

## Editing

- Edit task text, tags, and dates directly from the task view.
- Move tasks between repositories and tag groups.
- Toggle multiple selected tasks in one operation.
- Add confirmed deletion and undo for the latest operation.
- Support task templates and configurable creation workflows.

## Obsidian integration

- Open tasks through `obsidian://open` with correct URL encoding on macOS, Linux, and Windows.
- Support recurrence and the extended syntax of the Obsidian Tasks community plugin.
- Add a debounced filesystem watcher for automatic view refreshes.
- Collect tasks from multiple files in one vault through glob patterns.

## Project quality

- Expand unit and integration coverage with larger fixture vaults.
- Add StyLua and Selene checks to CI.
- Publish stable releases with migration notes and compatibility guarantees.
- Add a minimal reproduction template for bug reports.
