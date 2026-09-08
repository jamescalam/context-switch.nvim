-- context-switch: what is open where. A "project" is a directory; a project is
-- "open" when some tab's working directory (its :tcd, or the global cwd when it
-- has none) is that directory. Nothing is bookkept — the tabs are the truth,
-- so projects opened by hand with :tabnew + :tcd count too.

local M = {}

--- Canonical form of a directory path: normalized, no trailing slash.
function M.norm(p)
  p = vim.fs.normalize(p)
  if #p > 1 then
    p = p:gsub("/+$", "")
  end
  return p
end

--- Tabs that should not count as projects: anything flagged with the
--- `context_switch_ignore` tab variable, plus whatever `opts.ignore_tab` says.
function M.ignored(tab, opts)
  local ok, v = pcall(vim.api.nvim_tabpage_get_var, tab, "context_switch_ignore")
  if ok and v then
    return true
  end
  local f = opts and opts.ignore_tab
  return f ~= nil and f(tab) == true
end

--- Map of canonical path -> { path, tabs = { tabpage handles }, current }.
function M.open_projects(opts)
  local cur = vim.api.nvim_get_current_tabpage()
  local out = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if not M.ignored(tab, opts) then
      local nr = vim.api.nvim_tabpage_get_number(tab)
      local cwd = M.norm(vim.fn.getcwd(-1, nr))
      local e = out[cwd]
      if not e then
        e = { path = cwd, tabs = {}, current = false }
        out[cwd] = e
      end
      e.tabs[#e.tabs + 1] = tab
      if tab == cur then
        e.current = true
      end
    end
  end
  return out
end

--- The project of the current tab (canonical path).
function M.current()
  return M.norm(vim.fn.getcwd(-1, 0))
end

function M.jump(tab)
  if tab and vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    return true
  end
  return false
end

--- Point the current tab at `path` (tab-local cwd).
function M.switch_here(path, opts)
  path = M.norm(path)
  vim.cmd.tcd(vim.fn.fnameescape(path))
  vim.t.context_switch_project = path
  if opts and opts.on_switch then
    opts.on_switch(path)
  end
end

--- Open `path` in a fresh tab.
function M.open_new(path, opts)
  vim.cmd("tabnew")
  M.switch_here(path, opts)
  if opts and opts.on_open then
    opts.on_open(M.norm(path))
  end
end

--- Close a tab (any, not just the current one). Returns ok, err.
function M.close(tab)
  if not (tab and vim.api.nvim_tabpage_is_valid(tab)) then
    return false, "tab is gone"
  end
  if #vim.api.nvim_list_tabpages() == 1 then
    return false, "cannot close the last tab"
  end
  local nr = vim.api.nvim_tabpage_get_number(tab)
  local ok, err = pcall(vim.cmd, "tabclose " .. nr)
  if not ok then
    return false, (tostring(err):gsub("^.-:E%d+: ", ""))
  end
  return true
end

return M
