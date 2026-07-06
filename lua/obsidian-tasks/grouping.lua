local M = {}

local function node(name) return { name = name, order = {}, children = {}, tasks = {} } end

function M.group(tasks, untagged_label)
  local root = node(nil)
  for _, task in ipairs(tasks) do
    local tags = #task.tags > 0 and task.tags or { untagged_label or "Без тегов" }
    local current = root
    for _, tag in ipairs(tags) do
      if not current.children[tag] then
        current.children[tag] = node(tag)
        current.order[#current.order + 1] = tag
      end
      current = current.children[tag]
    end
    current.tasks[#current.tasks + 1] = task
  end
  return root
end

return M
