local calendar = require("obsidian-tasks.calendar")
local date = require("obsidian-tasks.date")
local date_input = require("obsidian-tasks.date_input")

local M = {}

local function notify(message) vim.notify("obsidian-tasks: " .. message, vim.log.levels.ERROR) end

local function input(options, callback)
  vim.ui.input({ prompt = options.prompt, default = options.input_default }, function(value)
    if value == nil then
      callback({ action = "cancel" })
      return
    end
    value = vim.trim(value)
    if value == "" then
      if options.fallback then
        callback({ action = "select", value = options.fallback })
      elseif options.allow_empty then
        callback({ action = "clear" })
      else
        callback({ action = "cancel" })
      end
      return
    end
    local normalized, error_message = date.parse(value, nil, options.display_format)
    if not normalized then
      notify(error_message)
      input(options, callback)
      return
    end
    callback({ action = "select", value = normalized })
  end)
end

M.input = input

function M.pick(options, callback)
  if options.picker == "input" then
    input(options, callback)
    return
  end
  calendar.open({
    title = options.title,
    initial = options.initial or options.fallback or date.today(),
    clearable = options.allow_empty,
    border = options.border,
    manual = function(selected, done)
      date_input.open({
        prompt = options.prompt,
        title = (options.title or "Date") .. " input",
        initial = selected,
        input_default = date.format(selected, options.display_format),
        allow_empty = options.allow_empty,
        display_format = options.display_format,
        border = options.border,
      }, done)
    end,
  }, callback)
end

return M
