local M = {}

local function is_leap_year(year)
  return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function days_in_month(year, month)
  local days = { 31, is_leap_year(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  return days[month]
end

local function components(value)
  if type(value) ~= "string" then
    return nil
  end
  local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  if not year or year < 1 or month < 1 or month > 12 or day < 1 or day > days_in_month(year, month) then
    return nil
  end
  return year, month, day
end

local function normalize_components(year, month, day)
  year, month, day = tonumber(year), tonumber(month), tonumber(day)
  if not year or not month or not day then
    return nil
  end
  local normalized = ("%04d-%02d-%02d"):format(year, month, day)
  return components(normalized) and normalized or nil
end

function M.today()
  return os.date("%Y-%m-%d")
end

function M.add_days(value, amount)
  local year, month, day = components(value)
  if not year then
    return nil, ("invalid date %q; expected YYYY-MM-DD"):format(value)
  end

  local step = amount < 0 and -1 or 1
  for _ = 1, math.abs(amount) do
    day = day + step
    if day > days_in_month(year, month) then
      day = 1
      month = month + 1
      if month > 12 then
        month = 1
        year = year + 1
      end
    elseif day < 1 then
      month = month - 1
      if month < 1 then
        month = 12
        year = year - 1
      end
      day = days_in_month(year, month)
    end
  end
  return ("%04d-%02d-%02d"):format(year, month, day)
end

local function escape_pattern(value)
  return (value:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end

local function parse_format(value, format)
  local pattern, fields = {}, {}
  local index = 1
  while index <= #format do
    local character = format:sub(index, index)
    if character ~= "%" then
      pattern[#pattern + 1] = escape_pattern(character)
      index = index + 1
    else
      local directive = format:sub(index + 1, index + 1)
      if directive == "Y" then
        pattern[#pattern + 1] = "(%d%d%d%d)"
        fields[#fields + 1] = "year"
      elseif directive == "m" then
        pattern[#pattern + 1] = "(%d+)"
        fields[#fields + 1] = "month"
      elseif directive == "d" then
        pattern[#pattern + 1] = "(%d+)"
        fields[#fields + 1] = "day"
      elseif directive == "%" then
        pattern[#pattern + 1] = "%%"
      else
        return nil
      end
      index = index + 2
    end
  end

  local captures = { value:match("^" .. table.concat(pattern) .. "$") }
  if #captures ~= #fields then
    return nil
  end
  local parts = {}
  for field_index, field in ipairs(fields) do
    if parts[field] then
      return nil
    end
    local capture = captures[field_index]
    if field ~= "year" and #capture > 2 then
      return nil
    end
    parts[field] = capture
  end
  if not parts.year or not parts.month or not parts.day then
    return nil
  end
  return normalize_components(parts.year, parts.month, parts.day)
end

function M.parse(input, today, display_format)
  local value = vim.trim(input or ""):lower()
  if value == "today" then
    value = today or M.today()
  elseif value == "tomorrow" then
    local result, error_message = M.add_days(today or M.today(), 1)
    if not result then
      return nil, error_message
    end
    value = result
  elseif value == "yesterday" then
    local result, error_message = M.add_days(today or M.today(), -1)
    if not result then
      return nil, error_message
    end
    value = result
  end

  if components(value) then
    return value
  end
  local iso_year, iso_month, iso_day = value:match("^(%d%d%d%d)%-(%d+)%-(%d+)$")
  if iso_month and #iso_month <= 2 and #iso_day <= 2 then
    local normalized = normalize_components(iso_year, iso_month, iso_day)
    if normalized then
      return normalized
    end
  end
  if display_format then
    local normalized = parse_format(value, display_format)
    if normalized then
      return normalized
    end
  end
  local expected = display_format and ("YYYY-MM-DD, " .. display_format) or "YYYY-MM-DD"
  return nil, ("invalid date %q; use %s, yesterday, today, or tomorrow"):format(input or "", expected)
end

function M.format(value, format)
  local year, month, day = components(value)
  if not year then
    return value
  end
  return os.date(format, os.time({ year = year, month = month, day = day, hour = 12 }))
end

function M.format_text(text, format)
  for _, marker in ipairs({ "➕", "🛫", "📅", "✅" }) do
    text = text:gsub(marker .. "%s*(%d%d%d%d%-%d%d%-%d%d)", function(value)
      return marker .. " " .. M.format(value, format)
    end)
  end
  return text
end

return M
