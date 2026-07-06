local config_module = require("obsidian-tasks.config")
local date = require("obsidian-tasks.date")
local parser = require("obsidian-tasks.parser")
local repository = require("obsidian-tasks.repository")
local ui = require("obsidian-tasks.ui")

local M = {}
local config

local function repository_label(repo) return repo.alias or repo.name end

local function notify(message, level)
  vim.notify("obsidian-tasks: " .. message, level or vim.log.levels.INFO)
end

local function ensure_setup()
  if not config then
    error("obsidian-tasks: call setup() before using the plugin", 2)
  end
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

local function select_primary_tag(repo, callback)
  local tags, error_message = repository.tags(repo)
  if not tags then
    notify(error_message, vim.log.levels.ERROR)
    return
  end
  local new_tag = "+ new tag..."
  tags[#tags + 1] = new_tag
  vim.ui.select(tags, { prompt = "Primary tag:" }, function(choice)
    if not choice then
      return
    end
    if choice ~= new_tag then
      callback(choice)
      return
    end
    vim.ui.input({ prompt = "New tag (without #): " }, function(input)
      if input and input ~= "" then
        local tag = input:sub(1, 1) == "#" and input or ("#" .. input)
        vim.schedule(function() callback(tag) end)
      end
    end)
  end)
end

local function select_additional_tags(repo, primary_tag, callback)
  if not config.creation.prompt_additional_tags then
    callback({})
    return
  end

  local available_tags, error_message = repository.tags(repo)
  if not available_tags then
    notify(error_message, vim.log.levels.ERROR)
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

  local cursor_index = 1
  local choose
  choose = function()
    local items = {}
    for _, tag in ipairs(tags) do
      items[#items + 1] = { kind = "tag", tag = tag }
    end
    items[#items + 1] = { kind = "new" }
    items[#items + 1] = { kind = "done" }

    vim.ui.select(items, {
      prompt = ("Additional tags (%d selected):"):format(#result()),
      snacks = {
        on_show = function(picker)
          for index, item in ipairs(picker:items()) do
            if item.idx == cursor_index then
              picker.list:view(index)
              break
            end
          end
        end,
      },
      format_item = function(item)
        if item.kind == "new" then
          return "+ new tag..."
        end
        if item.kind == "done" then
          return "Done"
        end
        return (selected[item.tag] and "[x] " or "[ ] ") .. item.tag
      end,
    }, function(choice, index)
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
          cursor_index = #tags
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

local function prompt_date(prompt, default, allow_empty, callback)
  vim.ui.input({ prompt = prompt }, function(input)
    if input == nil then
      return
    end
    local value = vim.trim(input)
    if value == "" then
      if default then
        callback(default)
      elseif allow_empty then
        callback(nil)
      end
      return
    end
    local normalized, error_message = date.parse(value, nil, config.dates.display_format)
    if not normalized then
      notify(error_message, vim.log.levels.ERROR)
      prompt_date(prompt, default, allow_empty, callback)
      return
    end
    callback(normalized)
  end)
end

local function create_in(repo)
  vim.ui.input({ prompt = "Task: " }, function(name)
    if not name or name == "" then
      return
    end
    select_primary_tag(repo, function(primary_tag)
      select_additional_tags(repo, primary_tag, function(additional_tags)
        local tags, seen = { primary_tag }, { [primary_tag] = true }
        for _, tag in ipairs(additional_tags) do
          if not seen[tag] then
            tags[#tags + 1] = tag
            seen[tag] = true
          end
        end
        local today = date.today()
        local start_default = config.creation.default_start_today and today or ""
        local start_default_display =
          start_default ~= "" and date.format(start_default, config.dates.display_format) or ""
        local due_example = date.format(assert(date.add_days(today, 1)), config.dates.display_format)
        prompt_date(
          "Start date [" .. start_default_display .. "]: ",
          start_default ~= "" and start_default or nil,
          true,
          function(start_date)
            prompt_date("Due date [e.g. " .. due_example .. "; empty = no deadline]: ", nil, true, function(due_date)
              local line = build_task_line(name, tags, start_date, due_date)
              local ok, error_message = repository.append(repo, { line = line, tags = tags })
              if not ok then
                notify(error_message, vim.log.levels.ERROR)
                return
              end
              notify("task added to " .. repository_label(repo) .. ": " .. table.concat(tags, " → "))
              ui.refresh_all()
            end)
          end)
      end)
    end)
  end)
end

function M.setup(options)
  config = config_module.setup(options)
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
  select_repository(function(repo)
    if repo then
      create_in(repo)
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
