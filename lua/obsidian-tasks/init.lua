local config_module = require("obsidian-tasks.config")
local parser = require("obsidian-tasks.parser")
local repository = require("obsidian-tasks.repository")
local ui = require("obsidian-tasks.ui")

local M = {}
local config

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
    format_item = function(repo) return repo.name end,
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
  local today = os.date("%Y-%m-%d")
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
        local today = os.date("%Y-%m-%d")
        local start_default = config.creation.default_start_today and today or ""
        vim.ui.input({ prompt = "Start date [" .. start_default .. "]: " }, function(start_input)
          if start_input == nil then
            return
          end
          local start_date = start_input ~= "" and start_input or (start_default ~= "" and start_default or nil)
          vim.ui.input({ prompt = "Due date [empty = no deadline]: " }, function(due_input)
            if due_input == nil then
              return
            end
            local line = build_task_line(name, tags, start_date, due_input ~= "" and due_input or nil)
            local ok, error_message = repository.append(repo, { line = line, tags = tags })
            if not ok then
              notify(error_message, vim.log.levels.ERROR)
              return
            end
            notify("task added to " .. repo.name .. ": " .. table.concat(tags, " → "))
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

return M
