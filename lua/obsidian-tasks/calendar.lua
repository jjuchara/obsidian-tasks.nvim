local date = require("obsidian-tasks.date")

local M = {}
local namespace = vim.api.nvim_create_namespace("obsidian-tasks-calendar")

local function month_start(value)
  local year, month = date.components(value)
  return ("%04d-%02d-01"):format(year, month)
end

local function month_grid(value)
  local year, month = date.components(value)
  local days = date.days_in_month(year, month)
  local timestamp = os.time({ year = year, month = month, day = 1, hour = 12 })
  local first_column = (tonumber(os.date("%w", timestamp)) + 6) % 7
  local weeks = {}
  for row = 1, 6 do
    weeks[row] = {}
    for column = 1, 7 do
      local day = (row - 1) * 7 + column - first_column
      weeks[row][column] = day >= 1 and day <= days and day or nil
    end
  end
  return weeks
end

M.month_grid = month_grid

local function centered(value, width)
  local padding = math.max(0, math.floor((width - vim.fn.strdisplaywidth(value)) / 2))
  return string.rep(" ", padding) .. value
end

function M.open(options, callback)
  local width = 36
  local selected = options.initial or date.today()
  if not date.components(selected) then
    selected = date.today()
  end
  local previous_window = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_create_buf(false, true)
  local window
  local finished = false

  local function finish(result)
    if finished then
      return
    end
    finished = true
    if window and vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
    if vim.api.nvim_win_is_valid(previous_window) then
      vim.api.nvim_set_current_win(previous_window)
    end
    callback(result)
  end

  local function render()
    local year, month, selected_day = date.components(selected)
    local first = month_start(selected)
    local weeks = month_grid(first)
    local title = date.format(first, "%B %Y")
    local lines = {
      centered(title, width),
      centered("Mo Tu We Th Fr Sa Su", width),
    }
    local selected_position
    local today_position
    local today = date.today()
    local today_year, today_month, today_day = date.components(today)
    local offset = math.floor((width - 21) / 2)
    for row, week in ipairs(weeks) do
      local cells = {}
      for column, day in ipairs(week) do
        cells[column] = day and ("%2d "):format(day) or "   "
        if day == selected_day then
          selected_position = { row = row + 1, column = offset + (column - 1) * 3 }
        end
        if year == today_year and month == today_month and day == today_day then
          today_position = { row = row + 1, column = offset + (column - 1) * 3 }
        end
      end
      lines[#lines + 1] = string.rep(" ", offset) .. table.concat(cells)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = centered("Enter select  x clear  i input", width)
    lines[#lines + 1] = centered("hjkl move  H/L month  t today", width)

    vim.bo[buffer].modifiable = true
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    vim.bo[buffer].modifiable = false
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
    if today_position then
      vim.api.nvim_buf_set_extmark(buffer, namespace, today_position.row, today_position.column, {
        end_col = today_position.column + 2,
        hl_group = "Special",
      })
    end
    if selected_position then
      vim.api.nvim_buf_set_extmark(buffer, namespace, selected_position.row, selected_position.column, {
        end_col = selected_position.column + 2,
        hl_group = "Visual",
      })
      if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_set_cursor(window, { selected_position.row + 1, selected_position.column })
      end
    end
  end

  local function move_days(amount)
    local next_date = date.add_days(selected, amount)
    if next_date then
      selected = next_date
      render()
    end
  end

  local function move_months(amount)
    local next_date = date.add_months(selected, amount)
    if next_date then
      selected = next_date
      render()
    end
  end

  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].filetype = "obsidian-tasks-calendar"
  window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - 13) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = 11,
    style = "minimal",
    border = options.border or "rounded",
    title = " " .. (options.title or "Select date") .. " ",
    title_pos = "center",
  })
  vim.wo[window].cursorline = false
  vim.wo[window].wrap = false

  local map_options = { buffer = buffer, silent = true, nowait = true }
  local function map(keys, action, description)
    for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set("n", key, action, vim.tbl_extend("force", map_options, { desc = description }))
    end
  end
  map({ "h", "<Left>" }, function() move_days(-1) end, "Previous day")
  map({ "l", "<Right>" }, function() move_days(1) end, "Next day")
  map({ "k", "<Up>" }, function() move_days(-7) end, "Previous week")
  map({ "j", "<Down>" }, function() move_days(7) end, "Next week")
  map({ "H", "<" }, function() move_months(-1) end, "Previous month")
  map({ "L", ">" }, function() move_months(1) end, "Next month")
  map("t", function()
    selected = date.today()
    render()
  end, "Select today")
  map("<CR>", function() finish({ action = "select", value = selected }) end, "Confirm date")
  map("x", function()
    if options.clearable then
      finish({ action = "clear" })
    end
  end, "Clear date")
  map("i", function()
    if not options.manual then
      return
    end
    options.manual(selected, function(result)
      if result.action == "cancel" then
        if vim.api.nvim_win_is_valid(window) then
          vim.api.nvim_set_current_win(window)
        end
        return
      end
      finish(result)
    end)
  end, "Enter date")
  map({ "q", "<Esc>" }, function() finish({ action = "cancel" }) end, "Cancel date")

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      if not finished then
        finish({ action = "cancel" })
      end
    end,
  })
  render()
  return { buf = buffer, win = window }
end

return M
