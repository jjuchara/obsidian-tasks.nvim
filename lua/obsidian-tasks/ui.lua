local date = require("obsidian-tasks.date")
local grouping = require("obsidian-tasks.grouping")
local repository = require("obsidian-tasks.repository")

local M = {}
local namespace = vim.api.nvim_create_namespace("obsidian-tasks")
local states = {}

local function notify(message, level)
  vim.notify("obsidian-tasks: " .. message, level or vim.log.levels.INFO)
end

local function is_valid(state)
  return vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_win_is_valid(state.win)
end

local function matches_status(task, status)
  return status == "all" or (status == "done" and task.done) or (status == "active" and not task.done)
end

local function add_line(output, line_map, highlights, text, highlight, task)
  output[#output + 1] = text
  if task then
    line_map[#output] = task
  end
  if highlight then
    highlights[#highlights + 1] = { #output - 1, highlight }
  end
end

local function deadline_bucket(task, today)
  if task.done or not task.due_date then
    return "#on-track"
  end
  if task.due_date < today then
    return "#overdue"
  end
  if task.due_date <= date.add_days(today, 1) then
    return "#due-soon"
  end
  return "#on-track"
end

local function task_highlight(task, today)
  if task.done then
    return "ObsidianTasksDone"
  end
  local bucket = deadline_bucket(task, today)
  if bucket == "#overdue" then
    return "ObsidianTasksOverdue"
  end
  if bucket == "#due-soon" then
    return "ObsidianTasksDueSoon"
  end
  return "ObsidianTasksTask"
end

local function render_node(node, depth, output, line_map, highlights, state, today)
  for _, name in ipairs(node.order) do
    local child = node.children[name]
    add_line(output, line_map, highlights, string.rep("  ", depth) .. "▾ " .. name, "ObsidianTasksTag")
    render_node(child, depth + 1, output, line_map, highlights, state, today)
  end
  for _, task in ipairs(node.tasks) do
    local checkbox = task.done and "[x] " or "[ ] "
    add_line(
      output,
      line_map,
      highlights,
      string.rep("  ", depth) .. checkbox .. date.format_text(task.text, state.config.dates.display_format),
      task_highlight(task, today),
      task
    )
  end
end

local sort_modes = { "source", "deadline", "title" }

function M.next_sort(current)
  for index, mode in ipairs(sort_modes) do
    if mode == current then
      return sort_modes[(index % #sort_modes) + 1]
    end
  end
  return sort_modes[1]
end

local function task_source_before(left, right)
  if left.path ~= right.path then
    return left.path < right.path
  end
  return left.lnum < right.lnum
end

local function sort_tasks(tasks, mode)
  if mode == "source" then
    return
  end
  table.sort(tasks, function(left, right)
    local left_value, right_value
    if mode == "deadline" then
      left_value, right_value = left.due_date, right.due_date
      if left_value == nil or right_value == nil then
        if left_value ~= right_value then
          return left_value ~= nil
        end
        return task_source_before(left, right)
      end
    else
      left_value, right_value = left.text:lower(), right.text:lower()
    end
    if left_value == right_value then
      return task_source_before(left, right)
    end
    return left_value < right_value
  end)
end

local function add_deadline_tags(tasks, today)
  local tagged = {}
  for _, task in ipairs(tasks) do
    local copy = vim.tbl_extend("force", {}, task)
    copy.tags = { deadline_bucket(task, today) }
    vim.list_extend(copy.tags, task.tags)
    tagged[#tagged + 1] = copy
  end
  return tagged
end

local function collect(state)
  local output, line_map, highlights = {}, {}, {}
  local today = date.today()
  for repo_index, repo in ipairs(state.repositories) do
    local tasks, error_message = repository.load(repo)
    if not tasks then
      add_line(output, line_map, highlights, "Error: " .. error_message, "DiagnosticError")
    else
      local filtered = {}
      for _, task in ipairs(tasks) do
        if matches_status(task, state.status) then
          filtered[#filtered + 1] = task
        end
      end
      sort_tasks(filtered, state.sort)
      if state.sort == "deadline" then
        filtered = add_deadline_tags(filtered, today)
      end

      if state.show_repository_headers then
        if repo_index > 1 then
          add_line(output, line_map, highlights, "")
        end
        add_line(output, line_map, highlights, "󰉋 " .. repo.name, "ObsidianTasksRepository")
      end

      if #filtered == 0 then
        add_line(output, line_map, highlights, "  No " .. state.status .. " tasks", "Comment")
      else
        render_node(
          grouping.group(filtered, "Без тегов"),
          state.show_repository_headers and 1 or 0,
          output,
          line_map,
          highlights,
          state,
          today
        )
      end
    end
  end
  return output, line_map, highlights
end

local function find_task_line(line_map, target)
  if not target then
    return nil
  end
  local raw_match, raw_distance
  for line, task in pairs(line_map) do
    if task.path == target.path and target.raw and task.raw == target.raw then
      local distance = math.abs(task.lnum - target.lnum)
      if not raw_distance or distance < raw_distance then
        raw_match, raw_distance = line, distance
      end
    end
  end
  if raw_match then
    return raw_match
  end
  for line, task in pairs(line_map) do
    if task.path == target.path and task.lnum == target.lnum then
      return line
    end
  end
  return nil
end

function M.refresh(state)
  if not is_valid(state) then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local cursor_task = state.cursor_target or state.line_map[cursor[1]]
  state.cursor_target = nil
  local output, line_map, highlights = collect(state)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, output)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  for _, item in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf, namespace, item[2], item[1], 0, -1)
  end
  state.line_map = line_map
  if #output > 0 then
    local task_line = find_task_line(line_map, cursor_task)
    vim.api.nvim_win_set_cursor(state.win, { task_line or math.min(cursor[1], #output), 0 })
  end
end

function M.refresh_all()
  for _, state in pairs(states) do
    M.refresh(state)
  end
end

function M.set_sort_all(mode)
  for _, state in pairs(states) do
    state.sort = mode
    M.refresh(state)
  end
end

local function current_task(state)
  return state.line_map[vim.api.nvim_win_get_cursor(state.win)[1]]
end

local function close(state)
  if state.tab_owned and vim.api.nvim_tabpage_is_valid(state.tab) and #vim.api.nvim_list_tabpages() > 1 then
    vim.api.nvim_set_current_tabpage(state.tab)
    vim.cmd.tabclose()
  elseif vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  states[state.buf] = nil
end

local function toggle(state)
  local task = current_task(state)
  if not task then
    notify("place the cursor on a task", vim.log.levels.WARN)
    return
  end
  local ok, result = repository.toggle(task, state.config.completion)
  if not ok then
    notify(result, vim.log.levels.ERROR)
    return
  end
  state.cursor_target = result
  M.refresh_all()
end

local function edit(state)
  local task = current_task(state)
  if not task then
    return
  end
  if state.config.view.type == "float" and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  states[state.buf] = nil
  vim.cmd.edit(vim.fn.fnameescape(task.path))
  vim.api.nvim_win_set_cursor(0, { task.lnum, 0 })
end

local statuses = { active = "done", done = "all", all = "active" }

local function map(state, lhs, callback, description)
  if type(lhs) == "table" then
    for _, key in ipairs(lhs) do
      map(state, key, callback, description)
    end
  elseif lhs then
    vim.keymap.set("n", lhs, callback, { buffer = state.buf, nowait = true, silent = true, desc = description })
  end
end

local function configure_buffer(state)
  local buf = state.buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "obsidian-tasks"
  vim.api.nvim_buf_set_name(buf, ("obsidian-tasks://%d"):format(buf))

  local mappings = state.config.mappings
  map(state, mappings.toggle, function() toggle(state) end, "Toggle task")
  map(state, mappings.edit, function() edit(state) end, "Edit task source")
  map(state, mappings.refresh, function() M.refresh(state) end, "Refresh tasks")
  map(state, mappings.close, function() close(state) end, "Close tasks")
  map(state, mappings.cycle_status, function()
    state.status = statuses[state.status]
    M.refresh(state)
    notify("status: " .. state.status)
  end, "Cycle task status")
  map(state, mappings.cycle_sort, function()
    state.sort = M.next_sort(state.sort)
    state.config.view.sort = state.sort
    M.refresh(state)
    notify("sort: " .. state.sort)
  end, "Cycle task sorting")

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function() states[buf] = nil end,
  })

  if state.config.view.type == "float" and state.config.view.close_on_leave then
    vim.api.nvim_create_autocmd("WinLeave", {
      buffer = buf,
      callback = function()
        vim.schedule(function()
          if states[buf] and is_valid(state) and vim.api.nvim_get_current_win() ~= state.win then
            close(state)
          end
        end)
      end,
    })
  end
end

local function open_window(config)
  local buf = vim.api.nvim_create_buf(false, true)
  local win
  if config.view.type == "float" then
    local width = math.max(20, math.floor(vim.o.columns * config.view.width))
    local height = math.max(5, math.floor(vim.o.lines * config.view.height))
    win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      width = width,
      height = height,
      style = "minimal",
      border = config.view.border,
      title = config.view.title,
      title_pos = "center",
    })
  else
    vim.cmd(config.view.window_command)
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
  end
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  return buf, win
end

local function create_state(config, repositories, options)
  local buf, win = open_window(config)
  local state = {
    buf = buf,
    win = win,
    tab = vim.api.nvim_get_current_tabpage(),
    tab_owned = options.tab_owned,
    repositories = repositories,
    show_repository_headers = options.show_repository_headers,
    status = config.view.status,
    sort = config.view.sort,
    config = config,
    line_map = {},
  }
  states[buf] = state
  configure_buffer(state)
  M.refresh(state)
  return state
end

function M.open(config)
  if config.view.repository_mode == "sections" then
    return create_state(config, config.repositories, { show_repository_headers = #config.repositories > 1 })
  end

  local opened = {}
  for _, repo in ipairs(config.repositories) do
    vim.cmd.tabnew()
    opened[#opened + 1] = create_state(config, { repo }, { tab_owned = true, show_repository_headers = false })
  end
  return opened
end

return M
