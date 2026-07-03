local parser = require("obsidian-tasks.parser")
local date = require("obsidian-tasks.date")
local grouping = require("obsidian-tasks.grouping")
local repository = require("obsidian-tasks.repository")

local function assert_equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(
      (message or "values differ") .. "\nactual: " .. vim.inspect(actual) .. "\nexpected: " .. vim.inspect(expected)
    )
  end
end

assert_equal(date.parse(" TODAY ", "2024-02-28"), "2024-02-28", "today alias must be normalized")
assert_equal(date.parse("Tomorrow", "2024-02-28"), "2024-02-29", "tomorrow must handle leap years")
assert_equal(date.parse("yesterday", "2024-03-01"), "2024-02-29", "yesterday must handle leap years")
assert_equal(
  date.parse("03.07.2026", "2026-07-03", "%d.%m.%Y"),
  "2026-07-03",
  "display-formatted dates must be normalized"
)
assert_equal(date.parse("2026-7-3"), "2026-07-03", "ISO input must allow dates without leading zeroes")
assert_equal(
  date.parse("3.7.2026", nil, "%d.%m.%Y"),
  "2026-07-03",
  "display-formatted input must allow dates without leading zeroes"
)
assert_equal(
  date.parse("7/3/2026", nil, "%m/%d/%Y"),
  "2026-07-03",
  "leading-zero normalization must respect the configured field order"
)
assert_equal(date.add_days("2024-12-31", 1), "2025-01-01", "date addition must cross year boundaries")
assert(not date.parse("2023-02-29"), "invalid calendar dates must be rejected")
assert(not date.parse("29.02.2023", nil, "%d.%m.%Y"), "invalid display-formatted dates must be rejected")
assert(not date.parse("0000-01-01"), "year zero must be rejected")
assert_equal(date.format("2026-07-03", "%d.%m.%Y"), "03.07.2026", "display format must use strftime")
assert_equal(
  date.format_text("➕ 2026-07-01 🛫 2026-07-02 📅 2026-07-03 ✅ 2026-07-04", "%d.%m.%Y"),
  "➕ 01.07.2026 🛫 02.07.2026 📅 03.07.2026 ✅ 04.07.2026",
  "all supported dates must be formatted"
)

local temp = vim.fn.tempname() .. ".md"
local repo = { name = "test", path = temp }
vim.fn.writefile({
  "---",
  "tags:",
  "  - ignored",
  "---",
  "# Tasks",
  "",
  "## #work",
  "",
  "- [ ] First #work #frontend ➕ 2026-07-01 🛫 2026-07-02 📅 2026-07-10",
  "- [x] Second ✅ 2026-07-01",
  "```md",
  "- [ ] Ignored #code",
  "```",
}, temp)

local tasks = assert(repository.load(repo))
assert_equal(#tasks, 2, "parser must ignore frontmatter and fenced code")
assert_equal(tasks[1].tags, { "#work", "#frontend" }, "inline tags must preserve order")
assert_equal(tasks[2].tags, { "#work" }, "heading tag must be used as fallback")
assert_equal(tasks[1].created_date, "2026-07-01", "creation date must be parsed")
assert_equal(tasks[1].start_date, "2026-07-02", "start date must be parsed")
assert_equal(
  parser.parse_tag_input("gantt, #frontend urgent gantt"),
  { "#gantt", "#frontend", "#urgent" },
  "additional tags must accept optional # and remove duplicates"
)

local tree = grouping.group(tasks)
assert(tree.children["#work"], "primary tag group is missing")
assert(tree.children["#work"].children["#frontend"], "nested tag group is missing")

local externally_changed = vim.fn.readfile(temp)
table.insert(externally_changed, 5, "<!-- external change -->")
vim.fn.writefile(externally_changed, temp)
assert(repository.toggle(tasks[1], { marker = "✅", date_format = "%Y-%m-%d" }))
local toggled = parser.parse_lines(vim.fn.readfile(temp), repo)
assert(toggled[1].done, "active task was not completed")
assert(toggled[1].completion_date, "completion date was not added")

assert(repository.toggle(toggled[1], { marker = "✅", date_format = "%Y-%m-%d" }))
local reopened = parser.parse_lines(vim.fn.readfile(temp), repo)
assert(not reopened[1].done, "completed task was not reopened")
assert(not reopened[1].completion_date, "completion date was not removed")

assert(repository.append(repo, {
  tags = { "#personal", "#urgent" },
  line = "- [ ] Third #personal #urgent ➕ 2026-07-02 ♾️",
}))
local final = parser.parse_lines(vim.fn.readfile(temp), repo)
assert_equal(#final, 3, "appended task is missing")
assert_equal(final[3].tags, { "#personal", "#urgent" })

local plugin = require("obsidian-tasks")
plugin.setup({ repositories = { repo } })
local original_input, original_select = vim.ui.input, vim.ui.select
local inputs = { "Created through UI", "gantt", "", "" }
vim.ui.input = function(_, callback)
  callback(table.remove(inputs, 1))
end
vim.ui.select = function(_, _, callback)
  callback("#work")
end
plugin.create()
vim.ui.input, vim.ui.select = original_input, original_select

local created = parser.parse_lines(vim.fn.readfile(temp), repo)
local created_through_ui = vim.iter(created):find(function(task)
  return task.text:find("Created through UI", 1, true) ~= nil
end)
assert(created_through_ui, "task created through UI is missing")
assert_equal(created_through_ui.tags, { "#work", "#gantt" }, "create flow must persist an additional tag")

local creation_today = date.today()
local creation_yesterday = assert(date.add_days(creation_today, -1))
local creation_tomorrow = assert(date.add_days(creation_today, 1))
local creation_tomorrow_input = ("%d.%d.%s"):format(
  tonumber(date.format(creation_tomorrow, "%d")),
  tonumber(date.format(creation_tomorrow, "%m")),
  date.format(creation_tomorrow, "%Y")
)
local relative_inputs = { "Flexible dates", "", "yesterday", creation_tomorrow_input }
local date_prompts = {}
vim.ui.input = function(options, callback)
  if options.prompt:find("date", 1, true) then
    date_prompts[#date_prompts + 1] = options.prompt
  end
  callback(table.remove(relative_inputs, 1))
end
vim.ui.select = function(_, _, callback)
  callback("#work")
end
plugin.create()
vim.ui.input, vim.ui.select = original_input, original_select

local relative_task = vim.iter(assert(repository.load(repo))):find(function(task)
  return task.text:find("Flexible dates", 1, true) ~= nil
end)
assert(relative_task, "task created with relative dates is missing")
assert_equal(relative_task.start_date, creation_yesterday, "yesterday input must be persisted as ISO")
assert_equal(relative_task.due_date, creation_tomorrow, "display-formatted input must be persisted as ISO")
assert_equal(
  date_prompts,
  {
    "Start date [" .. date.format(creation_today, "%d.%m.%Y") .. "]: ",
    "Due date [e.g. " .. date.format(creation_tomorrow, "%d.%m.%Y") .. "; empty = no deadline]: ",
  },
  "date prompt examples must use the configured display format"
)

local view_temp = vim.fn.tempname() .. ".md"
local view_repo = { name = "view-test", path = view_temp }
local today = date.today()
local yesterday = assert(date.add_days(today, -1))
local tomorrow = assert(date.add_days(today, 1))
local later = assert(date.add_days(today, 8))
vim.fn.writefile({
  "## #work",
  "- [ ] Zulu #work ➕ " .. yesterday .. " 🛫 " .. today .. " 📅 " .. tomorrow,
  "- [ ] Alpha #work 📅 " .. yesterday,
  "- [ ] Today #work 📅 " .. today,
  "- [x] Done #work ✅ " .. today,
  "- [ ] No deadline #work",
  "- [ ] Later #work 📅 " .. later,
}, view_temp)

plugin.setup({
  repositories = { view_repo },
  view = { type = "window", window_command = "botright new", status = "all", sort = "source" },
  dates = { display_format = "%d.%m.%Y" },
})
local state = plugin.open()
local rendered = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
assert(rendered:find("➕ " .. date.format(yesterday, "%d.%m.%Y"), 1, true), "creation date was not formatted")
assert(rendered:find("🛫 " .. date.format(today, "%d.%m.%Y"), 1, true), "start date was not formatted")
assert(rendered:find("📅 " .. date.format(tomorrow, "%d.%m.%Y"), 1, true), "due date was not formatted")
assert(rendered:find("✅ " .. date.format(today, "%d.%m.%Y"), 1, true), "completion date was not formatted")

local highlight_groups = {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(state.buf, -1, 0, -1, { details = true })) do
  local group = mark[4].hl_group
  highlight_groups[group] = (highlight_groups[group] or 0) + 1
end
assert(highlight_groups.ObsidianTasksOverdue, "overdue task highlight is missing")
assert_equal(highlight_groups.ObsidianTasksDueSoon, 2, "all due-soon tasks must use the warning highlight")

local status_notifications = {}
local original_notify = vim.notify
local cycle_status
vim.notify = function(message)
  status_notifications[#status_notifications + 1] = message
end
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(state.buf, "n")) do
  if mapping.lhs == "s" then
    assert(mapping.callback, "status mapping callback is missing")
    cycle_status = mapping.callback
    break
  end
end
assert(cycle_status, "status mapping is missing")
cycle_status()
assert_equal(state.status, "active", "status mapping did not cycle the task status")
assert_equal(status_notifications[1], "obsidian-tasks: status: active", "status mapping notification is incorrect")
cycle_status()
cycle_status()
vim.notify = original_notify

local function task_order(current_state)
  local result = {}
  for line = 1, vim.api.nvim_buf_line_count(current_state.buf) do
    local task = current_state.line_map[line]
    if task then
      result[#result + 1] = task.text:match("^(%S+)")
    end
  end
  return result
end

local zulu_line
for line, task in pairs(state.line_map) do
  if task.text:find("Zulu", 1, true) then
    zulu_line = line
  end
end
vim.api.nvim_win_set_cursor(state.win, { zulu_line, 0 })
plugin.sort("title")
assert_equal(task_order(state), { "Alpha", "Done", "Later", "No", "Today", "Zulu" }, "title sorting is incorrect")
local cursor_task = state.line_map[vim.api.nvim_win_get_cursor(state.win)[1]]
assert(cursor_task.text:find("Zulu", 1, true), "cursor task was not preserved")

plugin.sort("deadline")
assert_equal(task_order(state), { "Alpha", "Today", "Zulu", "Later", "Done", "No" }, "deadline sorting is incorrect")
local deadline_view = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
assert(deadline_view:find("#overdue", 1, true), "overdue deadline group is missing")
assert(deadline_view:find("#due-soon", 1, true), "due-soon deadline group is missing")
assert(deadline_view:find("#on-track", 1, true), "on-track deadline group is missing")
assert(
  deadline_view:find("#on-track", 1, true) < deadline_view:find("Later", 1, true),
  "later deadlines must be grouped as on-track"
)

local tabs_first = vim.fn.tempname() .. ".md"
local tabs_second = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "- [ ] Personal-only #personal" }, tabs_first)
vim.fn.writefile({ "- [ ] Frontend-only #frontend" }, tabs_second)
plugin.setup({
  repositories = {
    { name = "personal", alias = "Personal tasks", path = tabs_first },
    { name = "frontend", alias = "Frontend tasks", path = tabs_second },
  },
  view = {
    type = "window",
    window_command = "botright new",
    repository_mode = "tabs",
    status = "all",
  },
})
local tabpage_count = #vim.api.nvim_list_tabpages()
local tabs_state = plugin.open()
assert_equal(#vim.api.nvim_list_tabpages(), tabpage_count, "repository tabs must not create Neovim tabpages")
assert_equal(tabs_state.active_repository, 1, "the first repository tab must be active initially")
local tabs_rendered = table.concat(vim.api.nvim_buf_get_lines(tabs_state.buf, 0, -1, false), "\n")
assert(tabs_rendered:find("Personal-only", 1, true), "the active repository task is missing")
assert(not tabs_rendered:find("Frontend-only", 1, true), "an inactive repository task must not be rendered")
local winbar = vim.wo[tabs_state.win].winbar
assert(winbar:find("Personal tasks", 1, true), "the first repository alias is missing")
assert(winbar:find("Frontend tasks", 1, true), "the second repository alias is missing")
assert(not winbar:find("personal", 1, true), "the repository name must not be shown when an alias exists")

local next_repository
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(tabs_state.buf, "n")) do
  if mapping.desc == "Next task repository" then
    next_repository = mapping.callback
    break
  end
end
assert(next_repository, "next repository mapping is missing")
next_repository()
assert_equal(tabs_state.active_repository, 2, "next repository mapping did not activate the second tab")
tabs_rendered = table.concat(vim.api.nvim_buf_get_lines(tabs_state.buf, 0, -1, false), "\n")
assert(tabs_rendered:find("Frontend-only", 1, true), "the selected repository task is missing")
assert(not tabs_rendered:find("Personal-only", 1, true), "the previous repository task must not be rendered")
vim.api.nvim_win_close(tabs_state.win, true)

vim.cmd.runtime("plugin/obsidian-tasks.lua")
assert_equal(vim.fn.exists(":ObsidianTasksSort"), 2, "sort command is missing")
vim.cmd.ObsidianTasksSort("source")
assert_equal(state.sort, "source", "sort command did not update open views")

vim.uv.fs_unlink(temp)
vim.uv.fs_unlink(view_temp)
vim.uv.fs_unlink(tabs_first)
vim.uv.fs_unlink(tabs_second)
print("obsidian-tasks tests: OK")
