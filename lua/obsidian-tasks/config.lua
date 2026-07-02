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
  },
  creation = {
    default_start_today = true,
    prompt_additional_tags = true,
    infinity_marker = "♾️",
  },
  completion = {
    marker = "✅",
    date_format = "%Y-%m-%d",
  },
  mappings = {
    open = nil,
    create = nil,
    toggle = "<Space>",
    edit = "<CR>",
    refresh = "r",
    close = { "q", "<Esc>" },
    cycle_status = "s",
  },
}

local function fail(message)
  error("obsidian-tasks: " .. message, 3)
end

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

  local names = {}
  for index, repository in ipairs(config.repositories) do
    local repo = normalize_repository(repository, index)
    if names[repo.name] then
      fail(("repository name %q is duplicated"):format(repo.name))
    end
    names[repo.name] = true
    config.repositories[index] = repo
  end

  return config
end

return M
