local M = {}

M.defaults = {
  repositories = {},
  view = {
    type = "float",
    width = 0.5,
    height = 0.5,
    border = "rounded",
    title = " Obsidian tasks ",
    close_on_leave = true,
    repository_mode = "sections",
    window_command = "botright new",
    status = "active",
    sort = "source",
    filter = nil,
    fold_level = 99,
  },
  dates = {
    display_format = "%d.%m.%Y",
  },
  creation = {
    default_start_today = true,
    prompt_additional_tags = true,
    infinity_marker = "♾️",
  },
  completion = {
    marker = "✅",
  },
  mappings = {
    open = nil,
    create = nil,
    create_in_view = "a",
    toggle = "<Space>",
    edit = "<CR>",
    delete = "d",
    undo = "u",
    open_source = "gf",
    refresh = "r",
    close = { "q", "<Esc>" },
    cycle_status = "s",
    cycle_sort = "o",
    filter = "f",
    next_repository = "<Tab>",
    previous_repository = "<S-Tab>",
  },
}

local function fail(message) error("obsidian-tasks: " .. message, 3) end

local function normalize_repository(repository, index)
  local repo = vim.deepcopy(repository)
  repo.name = repo.name or ("repository-" .. index)

  if repo.path then
    repo.path = vim.fs.normalize(vim.fn.expand(repo.path))
  elseif repo.vault and repo.todo_file then
    repo.vault = vim.fs.normalize(vim.fn.expand(repo.vault))
    repo.path = vim.fs.joinpath(repo.vault, repo.todo_file)
  else
    fail(("repository %q must define path or vault + todo_file"):format(repo.name))
  end

  repo.path = vim.fs.normalize(vim.fn.expand(repo.path))
  repo.vault = repo.vault and vim.fs.normalize(vim.fn.expand(repo.vault)) or vim.fs.dirname(repo.path)
  return repo
end

local task_view_mappings = {
  "create_in_view",
  "toggle",
  "edit",
  "delete",
  "undo",
  "open_source",
  "refresh",
  "close",
  "cycle_status",
  "cycle_sort",
  "filter",
  "next_repository",
  "previous_repository",
}

local function validate_mapping_value(name, lhs, seen)
  if lhs == nil then
    return
  end
  if type(lhs) == "table" then
    for _, key in ipairs(lhs) do
      validate_mapping_value(name, key, seen)
    end
    return
  end
  if type(lhs) ~= "string" or lhs == "" then
    fail(("mappings.%s must be a non-empty string, a list of strings, or nil"):format(name))
  end
  if seen[lhs] then
    fail(("mappings.%s conflicts with mappings.%s on %q"):format(name, seen[lhs], lhs))
  end
  seen[lhs] = name
end

local function validate_task_view_mappings(mappings)
  local seen = {}
  for _, name in ipairs(task_view_mappings) do
    validate_mapping_value(name, mappings[name], seen)
  end
end

function M.setup(options)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), options or {})
  if #config.repositories == 0 then
    fail("repositories must contain at least one todo file")
  end
  if not vim.tbl_contains({ "float", "window" }, config.view.type) then
    fail("view.type must be 'float' or 'window'")
  end
  if not vim.tbl_contains({ "sections", "tabs" }, config.view.repository_mode) then
    fail("view.repository_mode must be 'sections' or 'tabs'")
  end
  if not vim.tbl_contains({ "active", "done", "all" }, config.view.status) then
    fail("view.status must be 'active', 'done', or 'all'")
  end
  if not vim.tbl_contains({ "source", "deadline", "title" }, config.view.sort) then
    fail("view.sort must be 'source', 'deadline', or 'title'")
  end
  if
    config.view.filter ~= nil
    and (type(config.view.filter) ~= "string" or not config.view.filter:match("^#[^%s#]+$"))
  then
    fail("view.filter must be a tag starting with '#'")
  end
  if type(config.view.fold_level) ~= "number" or config.view.fold_level < 0 or config.view.fold_level % 1 ~= 0 then
    fail("view.fold_level must be a non-negative integer")
  end
  if type(config.dates.display_format) ~= "string" or config.dates.display_format == "" then
    fail("dates.display_format must be a non-empty string")
  end
  local valid_format = pcall(os.date, config.dates.display_format, os.time())
  if not valid_format then
    fail("dates.display_format is not a valid strftime format")
  end
  validate_task_view_mappings(config.mappings)

  local names = {}
  for index, repository in ipairs(config.repositories) do
    local repo = normalize_repository(repository, index)
    if repo.alias ~= nil and (type(repo.alias) ~= "string" or repo.alias == "") then
      fail(("repository %q alias must be a non-empty string"):format(repo.name))
    end
    if names[repo.name] then
      fail(("repository name %q is duplicated"):format(repo.name))
    end
    names[repo.name] = true
    config.repositories[index] = repo
  end

  return config
end

return M
