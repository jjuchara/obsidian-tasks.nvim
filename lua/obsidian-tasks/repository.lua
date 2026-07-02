local parser = require("obsidian-tasks.parser")

local M = {}

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, ("cannot read %s"):format(path)
  end
  return lines
end

local function write_lines(path, lines)
  local temp = path .. ".obsidian-tasks.tmp"
  local original_stat = vim.uv.fs_stat(path)
  local ok, error_message = pcall(vim.fn.writefile, lines, temp)
  if not ok then
    return nil, error_message
  end
  if original_stat then
    local chmod_ok, chmod_error = vim.uv.fs_chmod(temp, original_stat.mode % 512)
    if not chmod_ok then
      pcall(vim.uv.fs_unlink, temp)
      return nil, chmod_error
    end
  end
  local renamed, rename_error = vim.uv.fs_rename(temp, path)
  if not renamed then
    pcall(vim.uv.fs_unlink, temp)
    return nil, rename_error
  end
  return true
end

function M.load(repository)
  local lines, error_message = read_lines(repository.path)
  if not lines then
    return nil, error_message
  end
  return parser.parse_lines(lines, repository)
end

local function locate(lines, task)
  if lines[task.lnum] == task.raw then
    return task.lnum
  end

  local matches = {}
  for index, line in ipairs(lines) do
    if line == task.raw then
      matches[#matches + 1] = index
    end
  end
  if #matches == 1 then
    return matches[1]
  end
  if #matches == 0 then
    return nil, "task changed or was removed; refresh the view"
  end
  return nil, "task is ambiguous after an external file change"
end

function M.toggle(task, completion)
  local lines, error_message = read_lines(task.path)
  if not lines then
    return nil, error_message
  end
  local lnum, locate_error = locate(lines, task)
  if not lnum then
    return nil, locate_error
  end

  local line = lines[lnum]
  if line:match("^%s*%- %[ %]") then
    line = line:gsub("^(%s*%- )%[ %]", "%1[x]", 1)
    if not line:find(completion.marker, 1, true) then
      line = line .. " " .. completion.marker .. " " .. os.date(completion.date_format)
    end
  elseif line:match("^%s*%- %[[xX]%]") then
    line = line:gsub("^(%s*%- )%[[xX]%]", "%1[ ]", 1)
    local escaped = vim.pesc(completion.marker)
    line = line:gsub("%s*" .. escaped .. "%s*%d%d%d%d%-%d%d%-%d%d", "")
  else
    return nil, "source line is no longer a task"
  end

  lines[lnum] = line
  return write_lines(task.path, lines)
end

function M.tags(repository)
  local tasks, error_message = M.load(repository)
  if not tasks then
    return nil, error_message
  end
  local tags, seen = {}, {}
  for _, task in ipairs(tasks) do
    for _, tag in ipairs(task.tags) do
      if not seen[tag] then
        tags[#tags + 1] = tag
        seen[tag] = true
      end
    end
  end
  return tags
end

function M.append(repository, task)
  local lines, error_message = read_lines(repository.path)
  if not lines then
    return nil, error_message
  end

  local primary_tag = task.tags[1]
  local heading = primary_tag and ("## " .. primary_tag) or nil
  local insert_at
  local found_heading = false

  if heading then
    for index, line in ipairs(lines) do
      if line == heading then
        found_heading = true
        insert_at = index
      elseif found_heading and line:match("^##%s+") then
        insert_at = index - 1
        break
      elseif found_heading and line:match("^%s*%- %[[ xX]%]") then
        insert_at = index
      end
    end
  end

  if not found_heading then
    if #lines > 0 and lines[#lines] ~= "" then
      lines[#lines + 1] = ""
    end
    if heading then
      lines[#lines + 1] = heading
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = task.line
  else
    table.insert(lines, insert_at + 1, task.line)
  end

  return write_lines(repository.path, lines)
end

return M
