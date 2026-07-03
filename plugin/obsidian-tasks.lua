if vim.g.loaded_obsidian_tasks then
  return
end
vim.g.loaded_obsidian_tasks = true

vim.api.nvim_create_user_command("ObsidianTasks", function()
  require("obsidian-tasks").open()
end, { desc = "Open Obsidian tasks" })

vim.api.nvim_create_user_command("ObsidianTasksCreate", function()
  require("obsidian-tasks").create()
end, { desc = "Create an Obsidian task" })

vim.api.nvim_create_user_command("ObsidianTasksRefresh", function()
  require("obsidian-tasks").refresh()
end, { desc = "Refresh open Obsidian task views" })

vim.api.nvim_create_user_command("ObsidianTasksSort", function(options)
  require("obsidian-tasks").sort(options.args ~= "" and options.args or nil)
end, {
  desc = "Set or cycle Obsidian task sorting",
  nargs = "?",
  complete = function() return { "source", "deadline", "title" } end,
})

vim.api.nvim_set_hl(0, "ObsidianTasksRepository", { link = "Title", default = true })
vim.api.nvim_set_hl(0, "ObsidianTasksTab", { link = "TabLine", default = true })
vim.api.nvim_set_hl(0, "ObsidianTasksTabActive", { link = "TabLineSel", default = true })
vim.api.nvim_set_hl(0, "ObsidianTasksTag", { link = "Identifier", default = true })
vim.api.nvim_set_hl(0, "ObsidianTasksTask", { link = "Normal", default = true })
vim.api.nvim_set_hl(0, "ObsidianTasksDone", { link = "Comment", default = true })
vim.api.nvim_set_hl(0, "ObsidianTasksOverdue", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "ObsidianTasksDueToday", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "ObsidianTasksDueSoon", { link = "DiagnosticWarn", default = true })
