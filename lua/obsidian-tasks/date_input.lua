local date = require("obsidian-tasks.date")

local M = {}

local function notify(message) vim.notify("obsidian-tasks: " .. message, vim.log.levels.ERROR) end

function M.open(options, callback)
  local previous_window = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_create_buf(false, true)
  local window
  local finished = false

  local function current_value() return vim.trim(vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] or "") end

  local function finish(result)
    if finished then
      return
    end
    finished = true
    vim.cmd("stopinsert")
    if window and vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
    if vim.api.nvim_win_is_valid(previous_window) then
      vim.api.nvim_set_current_win(previous_window)
    end
    callback(result)
  end

  local function confirm()
    local value = current_value()
    if value == "" then
      if options.fallback then
        finish({ action = "select", value = options.fallback })
      elseif options.allow_empty then
        finish({ action = "clear" })
      else
        finish({ action = "cancel" })
      end
      return
    end
    local normalized, error_message = date.parse(value, nil, options.display_format)
    if not normalized then
      notify(error_message)
      return
    end
    finish({ action = "select", value = normalized })
  end

  local function toggle()
    local normalized = date.parse(current_value(), nil, options.display_format)
    finish({ action = "toggle", value = normalized or options.initial })
  end

  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "obsidian-tasks-date-input"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { options.input_default or "" })

  local width = math.max(44, math.min(60, vim.fn.strdisplaywidth(options.input_default or "") + 12))
  window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - 3) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = 1,
    style = "minimal",
    border = options.border or "rounded",
    title = " " .. (options.title or "Enter date") .. " ",
    title_pos = "center",
    footer = " Enter select  Ctrl-I calendar  Esc cancel ",
    footer_pos = "center",
  })
  vim.wo[window].wrap = false

  local map_options = { buffer = buffer, silent = true, nowait = true }
  for _, mode in ipairs({ "n", "i" }) do
    vim.keymap.set(mode, "<CR>", confirm, vim.tbl_extend("force", map_options, { desc = "Confirm date input" }))
    vim.keymap.set(mode, "<C-i>", toggle, vim.tbl_extend("force", map_options, { desc = "Toggle date calendar" }))
    vim.keymap.set(
      mode,
      "<Esc>",
      function() finish({ action = "cancel" }) end,
      vim.tbl_extend("force", map_options, { desc = "Cancel date input" })
    )
  end

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      if not finished then
        finish({ action = "cancel" })
      end
    end,
  })

  vim.api.nvim_win_set_cursor(window, { 1, #current_value() })
  vim.cmd("startinsert!")
  return { buf = buffer, win = window }
end

return M
