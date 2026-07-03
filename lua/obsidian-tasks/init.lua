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
        callback(input:sub(1, 1) == "#" and input or ("#" .. input))
      end
    end)
  end)
end

local function select_additional_tags(callback)
  if not config.creation.prompt_additional_tags then
    callback({})
    return
  end
  vim.ui.input({ prompt = "Additional tags (tag, #tag; optional): " }, function(input)
    callback(parser.parse_tag_input(input))
  end)
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
      select_additional_tags(function(additional_tags)
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

return M
