-- Load guard. Commands and keymaps are registered from setup() so they can
-- honour user config; this file only prevents double-loading.
if vim.g.loaded_context_switch then
  return
end
vim.g.loaded_context_switch = true
