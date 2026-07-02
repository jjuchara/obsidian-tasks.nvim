local parser = require("obsidian-tasks.parser")
local grouping = require("obsidian-tasks.grouping")
local repository = require("obsidian-tasks.repository")

local function assert_equal(actual, expected, message)
  if not vim.deep_equal(actual, expected) then
    error((message or "values differ") .. "\nactual: " .. vim.inspect(actual) .. "\nexpected: " .. vim.inspect(expected))
  end
end

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
  "- [ ] First #work #frontend 📅 2026-07-10",
  "- [x] Second ✅ 2026-07-01",
  "```md",
  "- [ ] Ignored #code",
  "```",
}, temp)

local tasks = assert(repository.load(repo))
assert_equal(#tasks, 2, "parser must ignore frontmatter and fenced code")
assert_equal(tasks[1].tags, { "#work", "#frontend" }, "inline tags must preserve order")
assert_equal(tasks[2].tags, { "#work" }, "heading tag must be used as fallback")
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

vim.uv.fs_unlink(temp)
print("obsidian-tasks tests: OK")
