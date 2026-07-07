local config_module = require("obsidian-tasks.config")
local date = require("obsidian-tasks.date")
local parser = require("obsidian-tasks.parser")
local repository = require("obsidian-tasks.repository")
local ui = require("obsidian-tasks.ui")

local M = {}
local config

local function repository_label(repo) return repo.alias or repo.name end

local function notify(message, level) vim.notify("obsidian-tasks: " .. message, level or vim.log.levels.INFO) end

local function ensure_setup()
  if not config then
    error("obsidian-tasks: call setup() before using the plugin", 2)
  end
end

local tag_picker_hint = "Space toggle tag · Enter continue"

local function tag_picker_snacks_options()
  local function confirm_done(picker)
    picker.list:view(1)
    picker:action("confirm")
  end

  return {
    focus = "input",
    actions = {
      confirm_done = confirm_done,
      toggle_tag = function(picker, item)
        if item and item.item and item.item.kind == "tag" then
          item.item.toggle = true
          picker:action("confirm")
        end
      end,
    },
    win = {
      input = {
        footer = tag_picker_hint,
        footer_pos = "center",
        keys = {
          ["<CR>"] = { "confirm_done", mode = { "n", "i" }, desc = "Continue" },
          ["<Space>"] = { "toggle_tag", mode = { "n", "i" }, desc = "Toggle tag" },
        },
      },
      list = {
        footer = tag_picker_hint,
        footer_pos = "center",
        keys = {
          ["<CR>"] = "confirm_done",
          ["<Space>"] = "toggle_tag",
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
  local selected_tag
  local cursor_index
  local choose
  choose = function()
    local items = { { kind = "done" } }
    for _, tag in ipairs(tags) do
      items[#items + 1] = { kind = "tag", tag = tag }
    end
    items[#items + 1] = { kind = "new", label = new_tag }

    local select_options = {
      prompt = "Primary tag:",
      snacks = tag_picker_snacks_options(),
      format_item = function(item)
        if item.kind == "done" then
          return "Done"
        end
        if item.kind == "new" then
          return item.label
        end
        return (selected_tag == item.tag and "[x] " or "[ ] ") .. item.tag
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
      if not choice then
        if on_cancel then
          on_cancel()
        end
        return
      end
      if choice.kind == "done" then
        callback(selected_tag)
        return
      end
      if choice.kind == "tag" then
        if not choice.toggle then
          callback(choice.tag)
          return
        end
        selected_tag = selected_tag == choice.tag and nil or choice.tag
        vim.schedule(choose)
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
      snacks = tag_picker_snacks_options(),
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

local function build_task_line(name, tags, start_date, due_date)
  local today = date.today()
  local line = "- [ ] " .. name
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

local function prompt_date(prompt, default, allow_empty, callback, on_cancel)
  vim.ui.input({ prompt = prompt }, function(input)
    if input == nil then
      if on_cancel then
        on_cancel()
      end
      return
    end
    local value = vim.trim(input)
    if value == "" then
      if default then
        callback(default)
      elseif allow_empty then
        callback(nil)
      elseif on_cancel then
        on_cancel()
      end
      return
    end
    local normalized, error_message = date.parse(value, nil, config.dates.display_format)
    if not normalized then
      notify(error_message, vim.log.levels.ERROR)
      prompt_date(prompt, default, allow_empty, callback, on_cancel)
      return
    end
    callback(normalized)
  end)
end

local function create_in(repo, on_finish)
  vim.ui.input({ prompt = "Task: " }, function(name)
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
        prompt_date(
          "Start date [" .. start_default_display .. "]: ",
          start_default ~= "" and start_default or nil,
          true,
          function(start_date)
            prompt_date("Due date [e.g. " .. due_example .. "; empty = no deadline]: ", nil, true, function(due_date)
              local line = build_task_line(name, tags, start_date, due_date)
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
          end,
          on_finish
        )
      end, on_finish)
    end, on_finish)
  end)
end

function M.setup(options)
  config = config_module.setup(options)
  ui.set_create_callback(M.create)
  local mappings = config.mappings
  if mappings.open then
    vim.keymap.set("n", mappings.open, M.open, { desc = "Obsidian tasks: open" })
  end
  if mappings.create then
    vim.keymap.set("n", mappings.create, M.create, { desc = "Obsidian tasks: create" })
  end
  return config
end

function M.open()
  ensure_setup()
  return ui.open(config)
end

function M.create()
  ensure_setup()
  ui.set_task_flow_active(true)
  local finished = false
  local function finish()
    if finished then
      return
    end
    finished = true
    ui.set_task_flow_active(false)
  end
  local current_repository = ui.current_repository()
  if current_repository then
    create_in(current_repository, finish)
    return
  end
  select_repository(function(repo)
    if repo then
      create_in(repo, finish)
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
