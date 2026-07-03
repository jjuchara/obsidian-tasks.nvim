if vim.env.OBSIDIAN_TASKS_PROFILE ~= "dev" then
  return {}
end

local plugin_dir = assert(vim.env.OBSIDIAN_TASKS_PLUGIN_DIR, "OBSIDIAN_TASKS_PLUGIN_DIR is required")
local task_file = assert(vim.env.OBSIDIAN_TASKS_TASK_FILE, "OBSIDIAN_TASKS_TASK_FILE is required")

return {
  {
    "jjuchara/obsidian-tasks.nvim",
    dir = plugin_dir,
    opts = function(_, opts)
      opts = opts or {}
      opts.repositories = {
        {
          name = "dev",
          alias = "Plugin",
          path = task_file,
        },
      }
      return opts
    end,
  },
}
