local M = {}

local function extract_tags(text)
  local tags = {}
  local seen = {}
  for tag in text:gmatch("#([^%s#%[%]%(%){}<>,!%?;:`]+)") do
    tag = tag:gsub("[%.]+$", "")
    if tag ~= "" then
      tag = "#" .. tag
      if not seen[tag] then
        tags[#tags + 1] = tag
        seen[tag] = true
      end
    end
  end
  return tags
end

local function inline_tags(line, section_tag)
  local tags = extract_tags(line)
  if #tags == 0 and section_tag then
    return { section_tag }
  end
  return tags
end

function M.parse_lines(lines, repository)
  local tasks = {}
  local section_tag
  local in_frontmatter = lines[1] == "---"
  local in_fence = false

  for lnum, line in ipairs(lines) do
    if lnum > 1 and in_frontmatter and line == "---" then
      in_frontmatter = false
      goto continue
    end

    if not in_frontmatter then
      if line:match("^%s*```") or line:match("^%s*~~~") then
        in_fence = not in_fence
      elseif not in_fence then
        local heading_tag = line:match("^%s*##+%s+(#%S+)")
        if heading_tag then
          section_tag = heading_tag:gsub("[,;:%.]+$", "")
        else
          local indent, marker, text = line:match("^(%s*)%- %[([ xX])%]%s+(.*)$")
          if marker then
            tasks[#tasks + 1] = {
              repository = repository,
              path = repository.path,
              lnum = lnum,
              indent = indent,
              raw = line,
              text = text,
              done = marker:lower() == "x",
              tags = inline_tags(text, section_tag),
              created_date = text:match("➕%s*(%d%d%d%d%-%d%d%-%d%d)"),
              start_date = text:match("🛫%s*(%d%d%d%d%-%d%d%-%d%d)"),
              due_date = text:match("📅%s*(%d%d%d%d%-%d%d%-%d%d)"),
              completion_date = text:match("✅%s*(%d%d%d%d%-%d%d%-%d%d)"),
            }
          end
        end
      end
    end
    ::continue::
  end

  return tasks
end

function M.extract_tags(text)
  return extract_tags(text)
end

function M.parse_tag_input(input)
  local tags = {}
  local seen = {}
  for value in (input or ""):gmatch("[^,%s]+") do
    local tag = value:gsub("^#+", ""):gsub("[,;:%.]+$", "")
    if tag ~= "" then
      tag = "#" .. tag
      if not seen[tag] then
        tags[#tags + 1] = tag
        seen[tag] = true
      end
    end
  end
  return tags
end

return M
