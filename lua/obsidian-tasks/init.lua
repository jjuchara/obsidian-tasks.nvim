local config_module = require("obsidian-tasks.config")
local date = require("obsidian-tasks.date")
local date_picker = require("obsidian-tasks.date_picker")
local parser = require("obsidian-tasks.parser")
local repository = require("obsidian-tasks.repository")
local ui = require("obsidian-tasks.ui")

local M = {}
local config
local toggle_listeners = {}

local function repository_label(repo) return repo.alias or repo.name end

local function notify(message, level) vim.notify("obsidian-tasks: " .. message, level or vim.log.levels.INFO) end

local function ensure_setup()
  if not config then
    error("obsidian-tasks: call setup() before using the plugin", 2)
  end
end

local function emit_toggle(event)
  for _, callback in ipairs(vim.deepcopy(toggle_listeners)) do
    local ok, error_message = pcall(callback, event)
    if not ok then
      notify("task toggle listener failed: " .. tostring(error_message), vim.log.levels.ERROR)
    end
  end
end

local function tag_picker_snacks_options(hint, space_action, space_desc)
  local function confirm_done(picker)
    picker.list:view(1)
    picker:action("confirm")
  end

  return {
    focus = "input",
    actions = {
      confirm_done = confirm_done,
      select_tag = function(picker, item)
        if item and item.item and (item.item.kind == "tag" or item.item.kind == "new") then
          picker:action("confirm")
        end
      end,
      toggle_tag = function(picker, item)
        if item and item.item and item.item.kind == "new" then
          picker:action("confirm")
        elseif item and item.item and item.item.kind == "tag" then
          item.item.toggle = true
          picker:action("confirm")
        end
      end,
    },
    layout = {
      layout = {
        footer = hint,
        footer_pos = "center",
      },
    },
    win = {
      input = {
        keys = {
          ["<CR>"] = { "confirm_done", mode = { "n", "i" }, desc = "Continue" },
          ["<Space>"] = { space_action, mode = { "n", "i" }, desc = space_desc },
        },
      },
      list = {
        keys = {
          ["<CR>"] = "confirm_done",
          ["<Space>"] = space_action,
        },
      },
    },
  }
end

local function select_repository(callback)
  if #config.repositories == 1 then
    callback(config.repositories[1])
    return
  end
  vim.ui.select(config.repositories, {
    prompt = "Repository:",
    format_item = repository_label,
  }, callback)
end

local function select_primary_tag(repo, callback, on_cancel)
  local tags, error_message = repository.tags(repo)
  if not tags then
    notify(error_message, vim.log.levels.ERROR)
    if on_cancel then
      on_cancel()
    end
    return
  end
  local new_tag = "+ new tag..."
  local choose
  choose = function()
    local items = { { kind = "done" } }
    for _, tag in ipairs(tags) do
      items[#items + 1] = { kind = "tag", tag = tag }
    end
    items[#items + 1] = { kind = "new", label = new_tag }

    local select_options = {
      prompt = "Primary tag:",
      snacks = tag_picker_snacks_options("Space select tag · Enter continue", "select_tag", "Select tag"),
      format_item = function(item)
        if item.kind == "done" then
          return "Done"
        end
        if item.kind == "new" then
          return item.label
        end
        return item.tag
      end,
    }

    vim.ui.select(items, select_options, function(choice)
      if not choice then
        if on_cancel then
          on_cancel()
        end
        return
      end
      if choice.kind == "done" then
        callback(nil)
        return
      end
      if choice.kind == "tag" then
        callback(choice.tag)
        return
      end
      vim.ui.input({ prompt = "New tag (without #): " }, function(input)
        if input and input ~= "" then
          local parsed_tags = parser.parse_tag_input(input)
          vim.schedule(function() callback(parsed_tags[1]) end)
        elseif on_cancel then
          on_cancel()
        end
      end)
    end)
  end

  choose()
end

local function select_additional_tags(repo, primary_tag, callback, on_cancel)
  if not config.creation.prompt_additional_tags then
    callback({})
    return
  end

  local available_tags, error_message = repository.tags(repo)
  if not available_tags then
    notify(error_message, vim.log.levels.ERROR)
    if on_cancel then
      on_cancel()
    end
    return
  end

  local tags, known, selected, selected_order, ordered = {}, {}, {}, {}, {}
  for _, tag in ipairs(available_tags) do
    if tag ~= primary_tag and not known[tag] then
      tags[#tags + 1] = tag
      known[tag] = true
    end
  end

  local function add_selected(tag)
    if not known[tag] then
      tags[#tags + 1] = tag
      known[tag] = true
    end
    if not selected[tag] and tag ~= primary_tag then
      selected[tag] = true
      if not ordered[tag] then
        selected_order[#selected_order + 1] = tag
        ordered[tag] = true
      end
    end
  end

  local function result()
    local chosen = {}
    for _, tag in ipairs(selected_order) do
      if selected[tag] then
        chosen[#chosen + 1] = tag
      end
    end
    return chosen
  end

  local cursor_index
  local choose
  choose = function()
    local items = { { kind = "done" } }
    for _, tag in ipairs(tags) do
      items[#items + 1] = { kind = "tag", tag = tag }
    end
    items[#items + 1] = { kind = "new" }

    local select_options = {
      prompt = ("Additional tags (%d selected):"):format(#result()),
      snacks = tag_picker_snacks_options("Space toggle tag · Enter continue", "toggle_tag", "Toggle tag"),
      format_item = function(item)
        if item.kind == "new" then
          return "+ new tag..."
        end
        if item.kind == "done" then
          return "Done"
        end
        return (selected[item.tag] and "[x] " or "[ ] ") .. item.tag
      end,
    }
    if cursor_index then
      select_options.snacks.on_show = function(picker)
        for index, item in ipairs(picker:items()) do
          if item.idx == cursor_index then
            picker.list:view(index)
            break
          end
        end
      end
    end

    vim.ui.select(items, select_options, function(choice, index)
      cursor_index = index or cursor_index
      if not choice or choice.kind == "done" then
        callback(result())
        return
      end
      if choice.kind == "tag" then
        selected[choice.tag] = not selected[choice.tag]
        if selected[choice.tag] and not ordered[choice.tag] then
          selected_order[#selected_order + 1] = choice.tag
          ordered[choice.tag] = true
        end
        vim.schedule(choose)
        return
      end
      vim.ui.input({ prompt = "New additional tag (without #): " }, function(input)
        for _, tag in ipairs(parser.parse_tag_input(input)) do
          add_selected(tag)
          cursor_index = #tags + 1
        end
        vim.schedule(choose)
      end)
    end)
  end

  choose()
end

local function build_task_line(name, tags, start_date, due_date, description_suffix)
  local today = date.today()
  local line = "- [ ] " .. name
  if description_suffix then
    line = line .. " " .. description_suffix
  end
  if #tags > 0 then
    line = line .. " " .. table.concat(tags, " ")
  end
  line = line .. " ➕ " .. today
  if start_date then
    line = line .. " 🛫 " .. start_date
  end
  line = line .. (due_date and (" 📅 " .. due_date) or (" " .. config.creation.infinity_marker))
  return line
end

local function prompt_date(options, callback, on_cancel)
  date_picker.pick({
    picker = config.dates.picker,
    prompt = options.prompt,
    title = options.title,
    initial = options.initial,
    fallback = options.fallback,
    allow_empty = options.allow_empty,
    display_format = config.dates.display_format,
    border = config.view.border,
  }, function(result)
    if result.action == "cancel" then
      if on_cancel then
        on_cancel()
      end
      return
    end
    callback(result.action == "select" and result.value or nil)
  end)
end

local function create_in(repo, options, on_finish)
  vim.ui.input({ prompt = "Task: ", default = options.initial_name }, function(name)
    if not name or name == "" then
      if on_finish then
        on_finish()
      end
      return
    end
    select_primary_tag(repo, function(primary_tag)
      select_additional_tags(repo, primary_tag, function(additional_tags)
        local tags, seen = {}, {}
        if primary_tag then
          tags[#tags + 1] = primary_tag
          seen[primary_tag] = true
        end
        for _, tag in ipairs(additional_tags) do
          if not seen[tag] then
            tags[#tags + 1] = tag
            seen[tag] = true
          end
        end
        local today = date.today()
        local start_default = config.creation.default_start_today and today or ""
        local start_default_display = start_default ~= "" and date.format(start_default, config.dates.display_format)
          or ""
        local due_example = date.format(assert(date.add_days(today, 1)), config.dates.display_format)
        prompt_date({
          prompt = "Start date [" .. start_default_display .. "]: ",
          title = "Start date",
          initial = start_default ~= "" and start_default or today,
          fallback = start_default ~= "" and start_default or nil,
          allow_empty = true,
        }, function(start_date)
          prompt_date({
            prompt = "Due date [e.g. " .. due_example .. "; empty = no deadline]: ",
            title = "Due date",
            initial = start_date or assert(date.add_days(today, 1)),
            allow_empty = true,
          }, function(due_date)
            local line = build_task_line(name, tags, start_date, due_date, options.description_suffix)
            local ok, result = repository.append(repo, { line = line, tags = tags })
            if not ok then
              notify(result, vim.log.levels.ERROR)
              if on_finish then
                on_finish()
              end
              return
            end
            ui.set_undo(result.undo)
            ui.focus_all(result)
            local tag_path = #tags > 0 and table.concat(tags, " → ") or "no tags"
            notify("task added to " .. repository_label(repo) .. ": " .. tag_path)
            ui.refresh_all()
            if on_finish then
              on_finish()
            end
          end, on_finish)
        end, on_finish)
      end, on_finish)
    end, on_finish)
  end)
end

function M.setup(options)
  config = config_module.setup(options)
  ui.set_create_callback(M.create)
  ui.set_toggle_callback(emit_toggle)
  local mappings = config.mappings
  if mappings.open then
    vim.keymap.set("n", mappings.open, M.open, { desc = "Obsidian tasks: open" })
  end
  if mappings.create then
    vim.keymap.set("n", mappings.create, M.create, { desc = "Obsidian tasks: create" })
  end
  return config
end

function M.on_toggle(callback)
  if type(callback) ~= "function" then
    error("obsidian-tasks: toggle listener must be a function", 2)
  end
  toggle_listeners[#toggle_listeners + 1] = callback
  local active = true
  return function()
    if not active then
      return
    end
    active = false
    for index, registered in ipairs(toggle_listeners) do
      if registered == callback then
        table.remove(toggle_listeners, index)
        return
      end
    end
  end
end

function M.open()
  ensure_setup()
  return ui.open(config)
end

local function normalize_create_options(options)
  if options == nil then
    return {}
  end
  if type(options) ~= "table" then
    error("obsidian-tasks: create options must be a table", 3)
  end
  for _, name in ipairs({ "repository", "initial_name", "description_suffix" }) do
    local value = options[name]
    if value ~= nil and (type(value) ~= "string" or vim.trim(value) == "") then
      error(("obsidian-tasks: create option %s must be a non-empty string"):format(name), 3)
    end
    if type(value) == "string" and value:find("[\r\n]") then
      error(("obsidian-tasks: create option %s must be one line"):format(name), 3)
    end
  end
  return options
end

local function find_repository(name)
  return vim.iter(config.repositories):find(function(repo) return repo.name == name end)
end

function M.create(options)
  ensure_setup()
  options = normalize_create_options(options)
  ui.set_task_flow_active(true)
  local finished = false
  local function finish()
    if finished then
      return
    end
    finished = true
    ui.set_task_flow_active(false)
  end
  if options.repository then
    local selected_repository = find_repository(options.repository)
    if not selected_repository then
      finish()
      error(("obsidian-tasks: unknown repository %q"):format(options.repository), 2)
    end
    create_in(selected_repository, options, finish)
    return
  end
  local current_repository = ui.current_repository()
  if current_repository then
    create_in(current_repository, options, finish)
    return
  end
  select_repository(function(repo)
    if repo then
      create_in(repo, options, finish)
    else
      finish()
    end
  end)
end

function M.refresh()
  ensure_setup()
  ui.refresh_all()
end

function M.sort(mode)
  ensure_setup()
  local selected = mode or ui.next_sort(config.view.sort)
  if not vim.tbl_contains({ "source", "deadline", "title" }, selected) then
    error("obsidian-tasks: sort must be 'source', 'deadline', or 'title'", 2)
  end
  config.view.sort = selected
  ui.set_sort_all(selected)
  notify("sort: " .. selected)
end

function M.filter(tag)
  ensure_setup()
  local function apply(selected)
    config.view.filter = selected
    ui.set_filter_all(selected)
    notify(selected and ("filter: " .. selected) or "filter cleared")
  end

  if tag == nil then
    ui.select_filter(config.repositories, function(selected, confirmed)
      if confirmed then
        apply(selected)
      end
    end)
    return
  end
  if tag == "clear" then
    apply(nil)
    return
  end
  local tags = parser.parse_tag_input(tag)
  if #tags ~= 1 then
    error("obsidian-tasks: filter must be one tag or 'clear'", 2)
  end
  apply(tags[1])
end

return M
