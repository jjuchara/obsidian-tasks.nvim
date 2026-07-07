local date = require("obsidian-tasks.date")
local grouping = require("obsidian-tasks.grouping")
local parser = require("obsidian-tasks.parser")
local repository = require("obsidian-tasks.repository")

local M = {}
local namespace = vim.api.nvim_create_namespace("obsidian-tasks")
local states = {}
local filter_picker_active = false
local last_undo
local create_callback
local task_flow_active = false

_G.ObsidianTasksFoldText = function() return vim.fn.getline(vim.v.foldstart):gsub("▾ ", "▸ ", 1) end

local function repository_label(repo) return repo.alias or repo.name end

local function notify(message, level) vim.notify("obsidian-tasks: " .. message, level or vim.log.levels.INFO) end

local function filter_picker_snacks_options()
  return {
    focus = "input",
    actions = {
      apply_filter = function(picker, item)
        if item and item.item then
          picker:action("confirm")
        end
      end,
    },
    layout = {
      layout = {
        footer = "Space apply filter · Enter apply filter",
        footer_pos = "center",
      },
    },
    win = {
      input = {
        keys = {
          ["<CR>"] = { "confirm", mode = { "n", "i" }, desc = "Apply filter" },
          ["<Space>"] = { "apply_filter", mode = { "n", "i" }, desc = "Apply filter" },
        },
      },
      list = {
        keys = {
          ["<CR>"] = "confirm",
          ["<Space>"] = "apply_filter",
        },
      },
    },
  }
end

local function is_valid(state) return vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_win_is_valid(state.win) end

local function matches_status(task, status)
  return status == "all" or (status == "done" and task.done) or (status == "active" and not task.done)
end

local function matches_filter(task, tag_filter) return not tag_filter or vim.tbl_contains(task.tags, tag_filter) end

local function add_line(output, line_map, highlights, text, highlight, task)
  output[#output + 1] = text
  if task then
    line_map[#output] = task
  end
  if highlight then
    highlights[#highlights + 1] = { #output - 1, highlight }
  end
end

local function mapping_label(lhs)
  if type(lhs) == "table" then
    return table.concat(lhs, "/")
  end
  return lhs
end

local function footer_text(mappings)
  local items = {
    { mappings.create_in_view, "add" },
    { mappings.edit, "edit" },
    { mappings.toggle, "toggle" },
    { mappings.delete, "delete" },
    { mappings.undo, "undo" },
    { mappings.refresh, "refresh" },
    { mappings.filter, "filter" },
    { mappings.cycle_sort, "sort" },
    { mappings.cycle_status, "status" },
    { mappings.open_source, "source" },
    { mappings.close, "close" },
  }
  local labels = {}
  for _, item in ipairs(items) do
    local lhs = mapping_label(item[1])
    if lhs then
      labels[#labels + 1] = lhs .. " " .. item[2]
    end
  end
  return table.concat(labels, "  ")
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

local function render_node(node, depth, output, line_map, highlights, folds, fold_prefix, tag_path, state, today)
  for _, name in ipairs(node.order) do
    local child = node.children[name]
    local child_path = vim.list_extend(vim.deepcopy(tag_path), { name })
    local fold = {
      start = #output + 1,
      key = fold_prefix .. "\31" .. table.concat(child_path, "\31"),
      depth = #child_path,
    }
    folds[#folds + 1] = fold
    add_line(output, line_map, highlights, string.rep("  ", depth) .. "▾ " .. name, "ObsidianTasksTag")
    render_node(child, depth + 1, output, line_map, highlights, folds, fold_prefix, child_path, state, today)
    fold.finish = #output
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
  local output, line_map, highlights, folds = {}, {}, {}, {}
  local today = date.today()
  if state.tag_filter then
    add_line(output, line_map, highlights, "Filter: " .. state.tag_filter, "ObsidianTasksFilter")
    add_line(output, line_map, highlights, "")
  end
  local repositories = state.active_repository and { state.repositories[state.active_repository] } or state.repositories
  for repo_index, repo in ipairs(repositories) do
    local tasks, error_message = repository.load(repo)
    if not tasks then
      add_line(output, line_map, highlights, "Error: " .. error_message, "DiagnosticError")
    else
      local filtered = {}
      for _, task in ipairs(tasks) do
        if matches_status(task, state.status) and matches_filter(task, state.tag_filter) then
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
        add_line(output, line_map, highlights, "󰉋 " .. repository_label(repo), "ObsidianTasksRepository")
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
          folds,
          repo.name .. "\31" .. repo.path,
          {},
          state,
          today
        )
      end
    end
  end
  return output, line_map, highlights, folds
end

local function capture_fold_state(state)
  if not state.folds then
    return
  end
  vim.api.nvim_win_call(state.win, function()
    for _, fold in ipairs(state.folds) do
      local closed = vim.fn.foldclosed(fold.start)
      state.closed_folds[fold.key] = closed == fold.start or nil
      if closed == fold.start then
        vim.cmd(("silent %dfoldopen"):format(fold.start))
      end
    end
  end)
end

local function apply_folds(state, folds)
  vim.api.nvim_win_call(state.win, function()
    vim.cmd("silent! normal! zE")
    for index = #folds, 1, -1 do
      local fold = folds[index]
      if fold.finish > fold.start then
        vim.cmd(("silent %d,%dfold"):format(fold.start, fold.finish))
      end
    end
    vim.cmd("silent! normal! zR")
    for index = #folds, 1, -1 do
      local fold = folds[index]
      if state.closed_folds[fold.key] then
        vim.cmd(("silent %dfoldclose"):format(fold.start))
      end
    end
  end)
  state.folds = folds
end

local function update_repository_tabs(state)
  if not state.active_repository or not vim.api.nvim_win_is_valid(state.win) then
    return
  end
  local tabs = {}
  for index, repo in ipairs(state.repositories) do
    local highlight = index == state.active_repository and "ObsidianTasksTabActive" or "ObsidianTasksTab"
    local name = repository_label(repo):gsub("%%", "%%%%")
    tabs[#tabs + 1] = ("%%#%s#%%%d@v:lua.ObsidianTasksSelectRepository@ %s %%T"):format(highlight, index, name)
  end
  tabs[#tabs + 1] = "%#WinBar#"
  vim.wo[state.win].winbar = table.concat(tabs, " ")
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
  local output, line_map, highlights, folds = collect(state)
  capture_fold_state(state)
  if not state.folds_initialized then
    for _, fold in ipairs(folds) do
      if fold.depth > state.config.view.fold_level then
        state.closed_folds[fold.key] = true
      end
    end
    state.folds_initialized = true
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, output)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
  for _, item in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(state.buf, namespace, item[2], item[1], 0, -1)
  end
  apply_folds(state, folds)
  update_repository_tabs(state)
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

function M.set_filter_all(tag_filter)
  for _, state in pairs(states) do
    state.tag_filter = tag_filter
    M.refresh(state)
  end
end

function M.set_undo(undo) last_undo = undo end

function M.set_create_callback(callback) create_callback = callback end

function M.set_task_flow_active(active) task_flow_active = active end

function M.focus_all(target)
  for _, state in pairs(states) do
    state.cursor_target = target
  end
end

function M.current_repository()
  local win = vim.api.nvim_get_current_win()
  for _, state in pairs(states) do
    if state.win == win then
      if state.active_repository then
        return state.repositories[state.active_repository]
      end
      if #state.repositories == 1 then
        return state.repositories[1]
      end
      return nil
    end
  end
end

function M.select_filter(repositories, callback)
  local items = { { label = "Clear filter", tag = false } }
  local seen = {}
  for _, repo in ipairs(repositories) do
    local tags, error_message = repository.tags(repo)
    if not tags then
      notify(error_message, vim.log.levels.ERROR)
    else
      for _, tag in ipairs(tags) do
        if not seen[tag] then
          items[#items + 1] = { label = tag, tag = tag }
          seen[tag] = true
        end
      end
    end
  end
  filter_picker_active = true
  vim.ui.select(items, {
    prompt = "Filter by tag:",
    snacks = filter_picker_snacks_options(),
    format_item = function(item) return item.label end,
  }, function(choice)
    filter_picker_active = false
    callback(choice and (choice.tag or nil) or nil, choice ~= nil)
  end)
end

local function current_task(state) return state.line_map[vim.api.nvim_win_get_cursor(state.win)[1]] end

local function close(state)
  if vim.api.nvim_win_is_valid(state.win) then
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
  last_undo = result.undo
  state.cursor_target = result
  M.refresh_all()
end

local function delete_task(state)
  local task = current_task(state)
  if not task then
    notify("place the cursor on a task", vim.log.levels.WARN)
    return
  end
  local choice = vim.fn.confirm("Delete task?", "&Delete\n&Cancel", 2)
  if choice ~= 1 then
    return
  end
  local ok, result = repository.delete(task)
  if not ok then
    notify(result, vim.log.levels.ERROR)
    return
  end
  last_undo = result
  notify("task deleted; use undo to restore it")
  M.refresh_all()
end

local function undo_latest(state)
  if not last_undo then
    notify("nothing to undo", vim.log.levels.WARN)
    return
  end
  local ok, result = repository.undo(last_undo)
  if not ok then
    notify(result, vim.log.levels.ERROR)
    return
  end
  last_undo = nil
  state.cursor_target = result
  notify("operation undone")
  M.refresh_all()
end

local function open_source(state)
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

local function prompt_edit_date(state, label, current, callback)
  local default = current and date.format(current, state.config.dates.display_format) or ""
  vim.ui.input({ prompt = label .. " date: ", default = default }, function(input)
    if input == nil then
      return
    end
    local value = vim.trim(input)
    if value == "" then
      callback(nil)
      return
    end
    local normalized, error_message = date.parse(value, nil, state.config.dates.display_format)
    if not normalized then
      notify(error_message, vim.log.levels.ERROR)
      prompt_edit_date(state, label, current, callback)
      return
    end
    callback(normalized)
  end)
end

local function edit(state)
  local task = current_task(state)
  if not task then
    notify("place the cursor on a task", vim.log.levels.WARN)
    return
  end

  local text = parser.clean_task_text(task.text, {
    completion_marker = state.config.completion.marker,
    infinity_marker = state.config.creation.infinity_marker,
  })
  vim.ui.input({ prompt = "Task text: ", default = text }, function(text_input)
    if text_input == nil then
      return
    end
    local updated_text = vim.trim(text_input)
    if updated_text == "" then
      notify("task text cannot be empty", vim.log.levels.ERROR)
      edit(state)
      return
    end
    vim.ui.input({ prompt = "Tags: ", default = table.concat(task.tags, " ") }, function(tag_input)
      if tag_input == nil then
        return
      end
      local tags = parser.parse_tag_input(tag_input)
      prompt_edit_date(state, "Start", task.start_date, function(start_date)
        prompt_edit_date(state, "Due", task.due_date, function(due_date)
          local ok, result = repository.update(
            task,
            { text = updated_text, tags = tags, start_date = start_date, due_date = due_date },
            {
              completion_marker = state.config.completion.marker,
              infinity_marker = state.config.creation.infinity_marker,
            }
          )
          if not ok then
            notify(result, vim.log.levels.ERROR)
            return
          end
          last_undo = result.undo
          state.cursor_target = result
          notify("task updated")
          M.refresh_all()
        end)
      end)
    end)
  end)
end

local statuses = { active = "done", done = "all", all = "active" }

local function select_repository(state, index)
  if not state.active_repository or index < 1 or index > #state.repositories then
    return
  end
  state.active_repository = index
  M.refresh(state)
end

local function cycle_repository(state, offset)
  local count = #state.repositories
  select_repository(state, ((state.active_repository - 1 + offset) % count) + 1)
end

_G.ObsidianTasksSelectRepository = function(index)
  local win = vim.api.nvim_get_current_win()
  for _, state in pairs(states) do
    if state.win == win then
      select_repository(state, index)
      return
    end
  end
end

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
  vim.wo[state.win].foldmethod = "manual"
  vim.wo[state.win].foldcolumn = "1"
  vim.wo[state.win].foldtext = "v:lua.ObsidianTasksFoldText()"

  local mappings = state.config.mappings
  map(state, mappings.create_in_view, function()
    if create_callback then
      create_callback()
    end
  end, "Create task")
  map(state, mappings.toggle, function() toggle(state) end, "Toggle task")
  map(state, mappings.edit, function() edit(state) end, "Edit task")
  map(state, mappings.delete, function() delete_task(state) end, "Delete task")
  map(state, mappings.undo, function() undo_latest(state) end, "Undo latest task operation")
  map(state, mappings.open_source, function() open_source(state) end, "Open task source")
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
  map(state, mappings.filter, function()
    local repositories = state.repositories
    if state.active_repository then
      repositories = { state.repositories[state.active_repository] }
    end
    M.select_filter(repositories, function(tag_filter, confirmed)
      if not confirmed or not is_valid(state) then
        return
      end
      state.config.view.filter = tag_filter
      M.set_filter_all(tag_filter)
      notify(tag_filter and ("filter: " .. tag_filter) or "filter cleared")
    end)
  end, "Filter tasks by tag")
  map(state, mappings.next_repository, function() cycle_repository(state, 1) end, "Next task repository")
  map(state, mappings.previous_repository, function() cycle_repository(state, -1) end, "Previous task repository")

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function() states[buf] = nil end,
  })

  if state.config.view.type == "float" and state.config.view.close_on_leave then
    vim.api.nvim_create_autocmd("WinLeave", {
      buffer = buf,
      callback = function()
        if filter_picker_active or task_flow_active then
          return
        end
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
    local footer = footer_text(config.mappings)
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
      footer = footer ~= "" and (" " .. footer .. " ") or nil,
      footer_pos = "center",
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
    repositories = repositories,
    active_repository = options.active_repository,
    show_repository_headers = options.show_repository_headers,
    status = config.view.status,
    sort = config.view.sort,
    tag_filter = config.view.filter,
    config = config,
    line_map = {},
    closed_folds = {},
    folds = {},
    folds_initialized = false,
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
  return create_state(config, config.repositories, { active_repository = 1, show_repository_headers = false })
end

return M
