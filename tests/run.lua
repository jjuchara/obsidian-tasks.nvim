local parser = require("obsidian-tasks.parser")
local date = require("obsidian-tasks.date")
local grouping = require("obsidian-tasks.grouping")
local repository = require("obsidian-tasks.repository")
local config_module = require("obsidian-tasks.config")

local function assert_equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error(
      (message or "values differ") .. "\nactual: " .. vim.inspect(actual) .. "\nexpected: " .. vim.inspect(expected)
    )
  end
end

local function select_tag_item(items, tag)
  return vim.iter(items):find(function(item) return item.kind == "tag" and item.tag == tag end)
end

local function select_done_item(items)
  return vim.iter(items):find(function(item) return item.kind == "done" end)
end

local function select_new_item(items)
  return vim.iter(items):find(function(item) return item.kind == "new" end)
end

local function is_primary_tag_prompt(prompt) return prompt:find("Primary tag:", 1, true) ~= nil end

local function is_additional_tags_prompt(prompt) return prompt:find("Additional tags", 1, true) ~= nil end

local function chunks_text(value)
  if type(value) == "string" then
    return value
  end
  local parts = {}
  for _, chunk in ipairs(value or {}) do
    parts[#parts + 1] = type(chunk) == "table" and chunk[1] or chunk
  end
  return table.concat(parts)
end

local function assert_tag_picker_hotkeys(options, message, expected)
  assert(not options.prompt:find("Space ", 1, true), message .. " prompt must not duplicate hotkey hints")
  assert(options.snacks, message .. " must configure Snacks picker options")
  assert_equal(options.snacks.focus, "input", message .. " must focus the input")
  assert(options.snacks.actions.confirm_done, message .. " must define Enter continuation")
  assert(options.snacks.actions[expected.space_action], message .. " must define Space action")
  assert_equal(options.snacks.layout.layout.footer, expected.footer, message .. " layout footer is wrong")
  assert_equal(options.snacks.layout.layout.footer_pos, "center", message .. " layout footer position is wrong")
  assert_equal(options.snacks.win.input.footer, nil, message .. " input footer must not duplicate layout footer")
  assert_equal(options.snacks.win.list.footer, nil, message .. " list footer must not duplicate layout footer")
  assert_equal(options.snacks.win.input.keys["<CR>"][1], "confirm_done", message .. " input Enter mapping is wrong")
  assert_equal(
    options.snacks.win.input.keys["<Space>"][1],
    expected.space_action,
    message .. " input Space mapping is wrong"
  )
  assert_equal(options.snacks.win.list.keys["<CR>"], "confirm_done", message .. " list Enter mapping is wrong")
  assert_equal(
    options.snacks.win.list.keys["<Space>"],
    expected.space_action,
    message .. " list Space mapping is wrong"
  )
  assert_equal(options.snacks.win.input.keys["<Space>"].desc, expected.space_desc, message .. " Space desc is wrong")
end

local function assert_space_confirms_new_tag(options, message)
  local confirmed = false
  local picker = { action = function(_, action) confirmed = action == "confirm" end }
  options.snacks.actions[options.snacks.win.input.keys["<Space>"][1]](picker, { item = { kind = "new" } })
  assert(confirmed, message .. " Space must activate the new-tag item")
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
local ok, error_message = pcall(config_module.setup, {
  repositories = { repo },
  mappings = {
    edit = "<CR>",
    open_source = "<CR>",
  },
})
assert(not ok, "conflicting task-view mappings must be rejected")
assert(
  error_message:find('mappings.open_source conflicts with mappings.edit on "<CR>"', 1, true),
  "conflicting mapping error is unclear"
)

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
local completed_ok, completed_result = repository.toggle(tasks[1], { marker = "✅", date_format = "%Y-%m-%d" })
assert(completed_ok)
local toggled = parser.parse_lines(vim.fn.readfile(temp), repo)
assert(toggled[1].done, "active task was not completed")
assert(toggled[1].completion_date, "completion date was not added")
assert(repository.undo(completed_result.undo), "toggle undo failed")
local toggle_undone = parser.parse_lines(vim.fn.readfile(temp), repo)
assert(not toggle_undone[1].done, "toggle undo did not reopen the task")

assert(repository.toggle(toggle_undone[1], { marker = "✅", date_format = "%Y-%m-%d" }))
local toggled_again = parser.parse_lines(vim.fn.readfile(temp), repo)
assert(repository.toggle(toggled_again[1], { marker = "✅", date_format = "%Y-%m-%d" }))
local reopened = parser.parse_lines(vim.fn.readfile(temp), repo)
assert(not reopened[1].done, "completed task was not reopened")
assert(not reopened[1].completion_date, "completion date was not removed")

local update_ok, update_result = repository.update(reopened[1], {
  text = "Updated first",
  tags = { "#work", "#frontend", "#urgent", "#review" },
  start_date = "2026-07-03",
  due_date = nil,
}, {
  completion_marker = "✅",
  infinity_marker = "♾️",
})
assert(update_ok)
local updated = parser.parse_lines(vim.fn.readfile(temp), repo)
assert_equal(updated[1].text, "Updated first #work #frontend #urgent #review ➕ 2026-07-01 🛫 2026-07-03 ♾️")
assert_equal(updated[1].tags, { "#work", "#frontend", "#urgent", "#review" }, "updated task tags were not persisted")
assert_equal(updated[1].start_date, "2026-07-03", "updated task start date was not persisted")
assert_equal(updated[1].due_date, nil, "cleared task due date was not removed")
assert_equal(
  parser.clean_task_text(updated[1].text, { completion_marker = "✅", infinity_marker = "♾️" }),
  "Updated first",
  "task text cleanup must remove tags and date markers"
)
assert(repository.undo(update_result.undo), "update undo failed")
local update_undone = parser.parse_lines(vim.fn.readfile(temp), repo)
assert_equal(update_undone[1].text, reopened[1].text, "update undo did not restore the original task")
assert(repository.update(update_undone[1], {
  text = "Updated first",
  tags = { "#work", "#frontend", "#urgent", "#review" },
  start_date = "2026-07-03",
  due_date = nil,
}, {
  completion_marker = "✅",
  infinity_marker = "♾️",
}))
updated = parser.parse_lines(vim.fn.readfile(temp), repo)

local ok, delete_undo = repository.delete(updated[1])
assert(ok, "task deletion failed")
local after_delete = parser.parse_lines(vim.fn.readfile(temp), repo)
assert_equal(#after_delete, 1, "deleted task is still present")
assert(after_delete[1].text:find("Second", 1, true), "task deletion removed the wrong line")
local restored_ok = repository.restore_deleted(delete_undo)
assert(restored_ok, "deleted task was not restored")
local after_restore = parser.parse_lines(vim.fn.readfile(temp), repo)
assert_equal(#after_restore, 2, "restored task is missing")
assert_equal(after_restore[1].text, updated[1].text, "restored task content changed")
assert(not repository.restore_deleted(delete_undo), "restoring an already-present task must fail")

local append_ok, append_result = repository.append(repo, {
  tags = { "#personal", "#urgent" },
  line = "- [ ] Third #personal #urgent ➕ 2026-07-02 ♾️",
})
assert(append_ok)
local final = parser.parse_lines(vim.fn.readfile(temp), repo)
assert_equal(#final, 3, "appended task is missing")
assert_equal(final[3].tags, { "#personal", "#urgent" })
assert(repository.undo(append_result.undo), "append undo failed")
local append_undone = parser.parse_lines(vim.fn.readfile(temp), repo)
assert_equal(#append_undone, 2, "append undo did not remove the created task")
assert(repository.append(repo, {
  tags = { "#personal", "#urgent" },
  line = "- [ ] Third #personal #urgent ➕ 2026-07-02 ♾️",
}))

local plugin = require("obsidian-tasks")
plugin.setup({ repositories = { repo } })
local original_input, original_select = vim.ui.input, vim.ui.select
local inputs = { "Created through UI", "", "" }
vim.ui.input = function(options, callback)
  if options.prompt == "New additional tag (without #): " then
    callback("gantt")
  else
    callback(table.remove(inputs, 1))
  end
end
local additional_actions = { "#frontend", "#urgent", "new", "done" }
local visible_additional_tags = {}
local restored_additional_tag_cursors = {}
local initial_additional_tag_picker_kept_default_focus = false
local initial_additional_tag_picker_defaulted_to_done = false
vim.ui.select = function(items, options, callback)
  if is_primary_tag_prompt(options.prompt) then
    assert_tag_picker_hotkeys(options, "primary-tag picker", {
      footer = "Space select tag · Enter continue",
      space_action = "select_tag",
      space_desc = "Select tag",
    })
    assert_equal(
      options.format_item(select_tag_item(items, "#work")),
      "#work",
      "primary tags must not render checkboxes"
    )
    assert_space_confirms_new_tag(options, "primary-tag picker")
    callback(select_tag_item(items, "#work"))
    return
  end

  assert_tag_picker_hotkeys(options, "additional-tag picker", {
    footer = "Space toggle tag · Enter continue",
    space_action = "toggle_tag",
    space_desc = "Toggle tag",
  })
  assert_space_confirms_new_tag(options, "additional-tag picker")
  vim.list_extend(visible_additional_tags, vim.tbl_map(options.format_item, items))
  if options.snacks and options.snacks.on_show then
    options.snacks.on_show({
      items = function()
        return vim.tbl_map(function(index) return { idx = index } end, vim.fn.range(1, #items))
      end,
      list = {
        view = function(_, index) restored_additional_tag_cursors[#restored_additional_tag_cursors + 1] = index end,
      },
    })
  else
    initial_additional_tag_picker_kept_default_focus = options.snacks and options.snacks.focus == "input"
    initial_additional_tag_picker_defaulted_to_done = items[1] and items[1].kind == "done"
  end
  local action = table.remove(additional_actions, 1)
  local selected_index, selected_item = vim.iter(items):enumerate():find(
    function(_, candidate) return candidate.kind == action or candidate.tag == action end
  )
  callback(selected_item, selected_index)
end
plugin.create()
local created_through_ui
assert(
  vim.wait(1000, function()
    created_through_ui = vim
      .iter(parser.parse_lines(vim.fn.readfile(temp), repo))
      :find(function(task) return task.text:find("Created through UI", 1, true) ~= nil end)
    return created_through_ui ~= nil
  end),
  "task creation with multiple additional tags timed out"
)
vim.ui.input, vim.ui.select = original_input, original_select

assert(created_through_ui, "task created through UI is missing")
assert_equal(
  created_through_ui.tags,
  { "#work", "#frontend", "#urgent", "#gantt" },
  "create flow must persist selected existing tags and a new tag"
)
assert(vim.tbl_contains(visible_additional_tags, "[ ] #frontend"), "existing additional tags must be listed")
assert(vim.tbl_contains(visible_additional_tags, "[x] #frontend"), "selected additional tags must be highlighted")
assert(vim.tbl_contains(visible_additional_tags, "+ new tag..."), "the additional-tag list must offer a new tag")
assert(vim.tbl_contains(visible_additional_tags, "Done"), "the additional-tag list must offer completion")
assert(
  not vim.tbl_contains(visible_additional_tags, "Hotkeys: Space toggle tag · Enter continue"),
  "additional-tag hotkey hints must not be duplicated as list items"
)
assert(initial_additional_tag_picker_kept_default_focus, "the initial additional-tag picker must focus the input field")
assert(initial_additional_tag_picker_defaulted_to_done, "the initial additional-tag picker must default Enter to Done")
assert(
  vim.iter(restored_additional_tag_cursors):any(function(index) return index > 1 end),
  "the additional-tag picker must restore the cursor after toggling a lower tag"
)

local creation_today = date.today()
local creation_yesterday = assert(date.add_days(creation_today, -1))
local creation_tomorrow = assert(date.add_days(creation_today, 1))
local creation_tomorrow_input = ("%d.%d.%s"):format(
  tonumber(date.format(creation_tomorrow, "%d")),
  tonumber(date.format(creation_tomorrow, "%m")),
  date.format(creation_tomorrow, "%Y")
)
local relative_inputs = { "Flexible dates", "yesterday", creation_tomorrow_input }
local date_prompts = {}
vim.ui.input = function(options, callback)
  if options.prompt:find("date", 1, true) then
    date_prompts[#date_prompts + 1] = options.prompt
  end
  callback(table.remove(relative_inputs, 1))
end
vim.ui.select = function(items, options, callback)
  if is_primary_tag_prompt(options.prompt) then
    callback(select_tag_item(items, "#work"))
  else
    callback(select_done_item(items))
  end
end
plugin.create()
vim.ui.input, vim.ui.select = original_input, original_select

local relative_task = vim
  .iter(assert(repository.load(repo)))
  :find(function(task) return task.text:find("Flexible dates", 1, true) ~= nil end)
assert(relative_task, "task created with relative dates is missing")
assert_equal(relative_task.start_date, creation_yesterday, "yesterday input must be persisted as ISO")
assert_equal(relative_task.due_date, creation_tomorrow, "display-formatted input must be persisted as ISO")
assert_equal(date_prompts, {
  "Start date [" .. date.format(creation_today, "%d.%m.%Y") .. "]: ",
  "Due date [e.g. " .. date.format(creation_tomorrow, "%d.%m.%Y") .. "; empty = no deadline]: ",
}, "date prompt examples must use the configured display format")

local new_tag_temp = vim.fn.tempname() .. ".md"
vim.fn.writefile({ "## #existing", "- [ ] Existing task #existing" }, new_tag_temp)
plugin.setup({
  repositories = {
    repo,
    { name = "new-tag-test", path = new_tag_temp },
  },
})
local new_tag_input_active = false
vim.ui.select = function(items, options, callback)
  if options.prompt == "Repository:" then
    callback(items[2])
  elseif is_primary_tag_prompt(options.prompt) then
    callback(select_new_item(items))
  else
    callback(select_done_item(items))
  end
end
vim.ui.input = function(options, callback)
  if options.prompt == "Task: " then
    callback("Created with a new primary tag")
  elseif options.prompt == "New tag (without #): " then
    new_tag_input_active = true
    callback("new-primary")
    new_tag_input_active = false
  else
    assert(not new_tag_input_active, "the next prompt must wait until the new-tag input closes")
    callback("")
  end
end
plugin.create()
local new_tag_created = vim.wait(1000, function()
  return vim
    .iter(assert(repository.load({ name = "new-tag-test", path = new_tag_temp })))
    :any(function(task) return task.text:find("Created with a new primary tag", 1, true) ~= nil end)
end)
vim.ui.input, vim.ui.select = original_input, original_select
assert(new_tag_created, "task creation must continue after entering a new primary tag")
local new_tag_task = vim
  .iter(assert(repository.load({ name = "new-tag-test", path = new_tag_temp })))
  :find(function(task) return task.text:find("Created with a new primary tag", 1, true) ~= nil end)
assert_equal(new_tag_task.tags, { "#new-primary" }, "new primary tag must be persisted")
local original_repo_tasks = assert(repository.load(repo))
assert(
  not vim
    .iter(original_repo_tasks)
    :any(function(task) return task.text:find("Created with a new primary tag", 1, true) ~= nil end),
  "task with a new primary tag must be written only to the selected repository"
)

local no_tag_temp = vim.fn.tempname() .. ".md"
local no_tag_repo = { name = "no-tag-test", path = no_tag_temp }
vim.fn.writefile({ "# Tasks" }, no_tag_temp)
plugin.setup({ repositories = { no_tag_repo } })
local no_tag_inputs = { "Created without tags", "", "" }
vim.ui.input = function(_, callback) callback(table.remove(no_tag_inputs, 1)) end
vim.ui.select = function(items, options, callback)
  assert(is_primary_tag_prompt(options.prompt) or is_additional_tags_prompt(options.prompt))
  callback(select_done_item(items))
end
plugin.create()
vim.ui.input, vim.ui.select = original_input, original_select
local no_tag_task = vim
  .iter(assert(repository.load(no_tag_repo)))
  :find(function(task) return task.text:find("Created without tags", 1, true) ~= nil end)
assert(no_tag_task, "task creation without tags is missing")
assert_equal(no_tag_task.tags, {}, "continuing without a selected primary tag must create a tagless task")

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
assert(not rendered:find("Keys:", 1, true), "native task-view footers must not be rendered as buffer lines")
assert_equal(vim.wo[state.win].wrap, true, "task view must wrap long task lines")
assert_equal(vim.wo[state.win].linebreak, true, "task view must wrap long tasks at word boundaries")
assert_equal(vim.wo[state.win].breakindent, true, "wrapped task lines must keep readable indentation")

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
vim.notify = function(message) status_notifications[#status_notifications + 1] = message end
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

local original_filter_select = vim.ui.select
vim.ui.select = function(items, options, callback)
  assert_equal(options.prompt, "Filter by tag:", "filter picker prompt is incorrect")
  assert(options.snacks, "filter picker must configure Snacks picker options")
  assert_equal(options.snacks.focus, "input", "filter picker must focus the input")
  assert_equal(
    options.snacks.layout.layout.footer,
    "Space apply filter · Enter apply filter",
    "filter picker footer is wrong"
  )
  assert_equal(options.snacks.layout.layout.footer_pos, "center", "filter picker footer position is wrong")
  assert_equal(options.snacks.win.input.keys["<CR>"][1], "confirm", "filter picker input Enter mapping is wrong")
  assert_equal(
    options.snacks.win.input.keys["<Space>"][1],
    "apply_filter",
    "filter picker input Space mapping is wrong"
  )
  assert_equal(options.snacks.win.input.keys["<Space>"].desc, "Apply filter", "filter picker Space desc is wrong")
  assert_equal(options.snacks.win.list.keys["<CR>"], "confirm", "filter picker list Enter mapping is wrong")
  assert_equal(options.snacks.win.list.keys["<Space>"], "apply_filter", "filter picker list Space mapping is wrong")
  local confirmed = false
  options.snacks.actions.apply_filter(
    { action = function(_, action) confirmed = action == "confirm" end },
    { item = items[2] }
  )
  assert(confirmed, "filter picker Space must apply the highlighted filter")
  local selected = vim.iter(items):find(function(item) return item.tag == "#work" end)
  callback(selected)
end
plugin.filter()
vim.ui.select = original_filter_select
assert_equal(state.tag_filter, "#work", "selected tag filter was not applied")
assert_equal(
  task_order(state),
  { "Alpha", "Today", "Zulu", "Later", "Done", "No" },
  "tag filter removed matching tasks"
)
local filtered_view = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
assert(filtered_view:find("Filter: #work", 1, true), "active filter indicator is missing")
plugin.refresh()
assert_equal(state.tag_filter, "#work", "refresh did not preserve the active filter")
plugin.filter("personal")
assert_equal(task_order(state), {}, "tag filter kept tasks without the selected tag")
plugin.filter("clear")
assert_equal(state.tag_filter, nil, "clear did not remove the active filter")
assert_equal(task_order(state), { "Alpha", "Today", "Zulu", "Later", "Done", "No" }, "clear did not restore tasks")

local edit_task
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(state.buf, "n")) do
  if mapping.desc == "Edit task" then
    edit_task = mapping.callback
    break
  end
end
assert(edit_task, "edit mapping is missing")
for line, task in pairs(state.line_map) do
  if task.text:find("Zulu", 1, true) then
    vim.api.nvim_win_set_cursor(state.win, { line, 0 })
    break
  end
end
local edit_inputs = { "Renamed task", "#personal #urgent", "yesterday", "" }
vim.ui.input = function(_, callback) callback(table.remove(edit_inputs, 1)) end
edit_task()
vim.ui.input = original_input
local edited_task = vim
  .iter(assert(repository.load(view_repo)))
  :find(function(task) return task.text:find("Renamed task", 1, true) ~= nil end)
assert(edited_task, "edited task is missing")
assert_equal(edited_task.tags, { "#personal", "#urgent" }, "edit flow did not persist tags")
assert_equal(edited_task.start_date, yesterday, "edit flow did not persist the start date")
assert_equal(edited_task.due_date, nil, "edit flow did not clear the due date")
assert(edited_task.text:find("♾️", 1, true), "edit flow did not persist the no-deadline marker")

local create_task, delete_task, undo_latest
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(state.buf, "n")) do
  if mapping.desc == "Create task" then
    create_task = mapping.callback
  elseif mapping.desc == "Delete task" then
    delete_task = mapping.callback
  elseif mapping.desc == "Undo latest task operation" then
    undo_latest = mapping.callback
  end
end
assert(create_task, "create mapping is missing")
assert(delete_task, "delete mapping is missing")
assert(undo_latest, "undo mapping is missing")
undo_latest()
assert(
  not vim
    .iter(assert(repository.load(view_repo)))
    :any(function(task) return task.text:find("Renamed task", 1, true) ~= nil end),
  "undo did not revert the edited task"
)
assert(
  vim.iter(assert(repository.load(view_repo))):any(function(task) return task.text:find("Zulu", 1, true) ~= nil end),
  "undo did not restore the original task text"
)

for line, task in pairs(state.line_map) do
  if task.text:find("Zulu", 1, true) then
    vim.api.nvim_win_set_cursor(state.win, { line, 0 })
    break
  end
end
edit_inputs = { "Renamed task", "#personal #urgent", "yesterday", "" }
vim.ui.input = function(_, callback) callback(table.remove(edit_inputs, 1)) end
edit_task()
vim.ui.input = original_input
for line, task in pairs(state.line_map) do
  if task.text:find("Renamed task", 1, true) then
    vim.api.nvim_win_set_cursor(state.win, { line, 0 })
    break
  end
end
local original_confirm = vim.fn.confirm
vim.fn.confirm = function() return 1 end
delete_task()
vim.fn.confirm = original_confirm
assert(
  not vim
    .iter(assert(repository.load(view_repo)))
    :any(function(task) return task.text:find("Renamed task", 1, true) ~= nil end),
  "confirmed task deletion did not remove the task"
)
undo_latest()
assert(
  vim
    .iter(assert(repository.load(view_repo)))
    :any(function(task) return task.text:find("Renamed task", 1, true) ~= nil end),
  "undo did not restore the deleted task"
)

local create_inputs = { "Created then undone", "", "" }
vim.ui.input = function(_, callback) callback(table.remove(create_inputs, 1)) end
vim.ui.select = function(items, options, callback)
  if is_primary_tag_prompt(options.prompt) then
    callback(select_tag_item(items, "#work"))
  else
    callback(select_done_item(items))
  end
end
create_task()
vim.ui.input, vim.ui.select = original_input, original_select
assert(
  vim.wait(1000, function()
    return vim
      .iter(assert(repository.load(view_repo)))
      :any(function(task) return task.text:find("Created then undone", 1, true) ~= nil end)
  end),
  "task created from the task view is missing"
)
assert(vim.api.nvim_win_is_valid(state.win), "creating from the task view closed the task view")
undo_latest()
assert(
  not vim
    .iter(assert(repository.load(view_repo)))
    :any(function(task) return task.text:find("Created then undone", 1, true) ~= nil end),
  "undo did not remove the created task"
)

local open_source_task
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(state.buf, "n")) do
  if mapping.desc == "Open task source" then
    open_source_task = mapping.callback
    break
  end
end
assert(open_source_task, "open source mapping is missing")

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
local command_create_inputs = { "Created by command", "", "" }
vim.ui.input = function(_, callback) callback(table.remove(command_create_inputs, 1)) end
vim.ui.select = function(items, options, callback)
  assert(options.prompt ~= "Repository:", "create command must use the active task-view repository")
  if is_primary_tag_prompt(options.prompt) then
    callback(select_tag_item(items, "#frontend"))
  else
    callback(select_done_item(items))
  end
end
plugin.create()
vim.ui.input, vim.ui.select = original_input, original_select
assert(
  not vim
    .iter(assert(repository.load({ path = tabs_first })))
    :any(function(task) return task.text:find("Created by command", 1, true) ~= nil end),
  "create command used the inactive repository while a task view was open"
)
assert(
  vim
    .iter(assert(repository.load({ path = tabs_second })))
    :any(function(task) return task.text:find("Created by command", 1, true) ~= nil end),
  "create command did not use the active task-view repository"
)
local tabs_cursor_task = tabs_state.line_map[vim.api.nvim_win_get_cursor(tabs_state.win)[1]]
assert(tabs_cursor_task.text:find("Created by command", 1, true), "create command did not focus the new task")
vim.api.nvim_win_close(tabs_state.win, true)

local folds_temp = vim.fn.tempname() .. ".md"
vim.fn.writefile({
  "- [ ] Frontend task #work #frontend",
  "- [ ] Backend task #work #backend",
}, folds_temp)
plugin.setup({
  repositories = { { name = "folds", path = folds_temp } },
  view = { type = "window", window_command = "botright new", status = "all" },
})
local folds_state = plugin.open()
assert_equal(vim.wo[folds_state.win].foldmethod, "manual", "task groups must use native manual folds")
assert_equal(vim.wo[folds_state.win].foldcolumn, "1", "task view must expose the native fold column")

local function fold_line(current_state, suffix)
  for _, fold in ipairs(current_state.folds) do
    if fold.key:sub(-#suffix) == suffix then
      return fold.start
    end
  end
end

local work_fold = assert(fold_line(folds_state, "#work"), "parent tag fold is missing")
local frontend_fold = assert(fold_line(folds_state, "#frontend"), "nested tag fold is missing")
vim.api.nvim_win_set_cursor(folds_state.win, { frontend_fold, 0 })
vim.cmd("normal! zc")
vim.api.nvim_win_set_cursor(folds_state.win, { work_fold, 0 })
vim.cmd("normal! zc")
assert_equal(vim.fn.foldclosed(work_fold), work_fold, "parent tag group did not collapse")

plugin.refresh()
work_fold = assert(fold_line(folds_state, "#work"), "parent tag fold disappeared after refresh")
frontend_fold = assert(fold_line(folds_state, "#frontend"), "nested tag fold disappeared after refresh")
assert_equal(vim.fn.foldclosed(work_fold), work_fold, "refresh did not preserve the collapsed parent group")
vim.api.nvim_win_set_cursor(folds_state.win, { work_fold, 0 })
vim.cmd("normal! zo")
assert_equal(vim.fn.foldclosed(frontend_fold), frontend_fold, "refresh did not preserve the collapsed nested group")
assert(vim.fn.foldtextresult(frontend_fold):find("▸ #frontend", 1, true), "collapsed fold marker is incorrect")
vim.api.nvim_win_close(folds_state.win, true)

plugin.setup({
  repositories = { { name = "folds-collapsed", path = folds_temp } },
  view = { type = "window", window_command = "botright new", status = "all", fold_level = 0 },
})
local collapsed_state = plugin.open()
local collapsed_work_fold = assert(fold_line(collapsed_state, "#work"), "initially collapsed tag fold is missing")
assert_equal(
  vim.fn.foldclosed(collapsed_work_fold),
  collapsed_work_fold,
  "fold_level = 0 must initially collapse top-level groups"
)
vim.api.nvim_win_close(collapsed_state.win, true)

plugin.setup({
  repositories = { view_repo },
  view = { type = "float", close_on_leave = true, status = "all" },
})
local float_state = plugin.open()
local float_config = vim.api.nvim_win_get_config(float_state.win)
local float_footer = chunks_text(float_config.footer)
assert(float_footer:find("a add", 1, true), "floating task view footer must show the create mapping")
assert(float_footer:find("u undo", 1, true), "floating task view footer must show the undo mapping")
assert(float_footer:find("q/<Esc> close", 1, true), "floating task view footer must show list mappings")
local original_float_select = vim.ui.select
vim.ui.select = function(items, _, callback)
  local picker_buf = vim.api.nvim_create_buf(false, true)
  local picker_win = vim.api.nvim_open_win(picker_buf, true, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 30,
    height = 5,
    style = "minimal",
  })
  local selected = vim.iter(items):find(function(item) return item.tag == "#work" end)
  callback(selected)
  vim.api.nvim_win_close(picker_win, true)
end
plugin.filter()
vim.ui.select = original_float_select
assert(vim.api.nvim_buf_is_valid(float_state.buf), "filter picker closed the floating task buffer")
assert(vim.api.nvim_win_is_valid(float_state.win), "filter picker closed the floating task window")
assert_equal(float_state.tag_filter, "#work", "floating task view did not apply the selected filter")
assert_equal(vim.api.nvim_get_current_win(), float_state.win, "filter picker did not return to the task view")

local float_create_task
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(float_state.buf, "n")) do
  if mapping.desc == "Create task" then
    float_create_task = mapping.callback
    break
  end
end
assert(float_create_task, "floating task view create mapping is missing")

local function with_prompt_window(callback)
  local prompt_buf = vim.api.nvim_create_buf(false, true)
  local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    row = 2,
    col = 2,
    width = 30,
    height = 3,
    style = "minimal",
  })
  callback()
  if vim.api.nvim_win_is_valid(prompt_win) then
    vim.api.nvim_win_close(prompt_win, true)
  end
end

local float_create_inputs = { "Created in float", "", "" }
vim.ui.input = function(_, callback)
  with_prompt_window(function() callback(table.remove(float_create_inputs, 1)) end)
end
vim.ui.select = function(items, options, callback)
  with_prompt_window(function()
    if is_primary_tag_prompt(options.prompt) then
      callback(select_tag_item(items, "#work"))
    else
      callback(select_done_item(items))
    end
  end)
end
float_create_task()
vim.ui.input, vim.ui.select = original_input, original_select
assert(
  vim.wait(1000, function()
    return vim
      .iter(assert(repository.load(view_repo)))
      :any(function(task) return task.text:find("Created in float", 1, true) ~= nil end)
  end),
  "task created from the floating task view is missing"
)
assert(vim.api.nvim_buf_is_valid(float_state.buf), "creating from the floating task view closed the buffer")
assert(vim.api.nvim_win_is_valid(float_state.win), "creating from the floating task view closed the window")
local float_cursor_task = float_state.line_map[vim.api.nvim_win_get_cursor(float_state.win)[1]]
assert(float_cursor_task.text:find("Created in float", 1, true), "created task was not focused")
vim.api.nvim_win_close(float_state.win, true)

vim.cmd.runtime("plugin/obsidian-tasks.lua")
assert_equal(vim.fn.exists(":ObsidianTasksSort"), 2, "sort command is missing")
assert_equal(vim.fn.exists(":ObsidianTasksFilter"), 2, "filter command is missing")
vim.cmd.ObsidianTasksSort("source")
assert_equal(state.sort, "source", "sort command did not update open views")

vim.uv.fs_unlink(temp)
vim.uv.fs_unlink(new_tag_temp)
vim.uv.fs_unlink(no_tag_temp)
vim.uv.fs_unlink(view_temp)
vim.uv.fs_unlink(tabs_first)
vim.uv.fs_unlink(tabs_second)
vim.uv.fs_unlink(folds_temp)
print("obsidian-tasks tests: OK")
