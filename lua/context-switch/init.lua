-- context-switch.nvim: switch projects (directories) from a floating picker.
-- A project is open when a tab's working directory is it; the picker shows
-- those on their own background and jumps to them instead of reopening.

local tabs = require("context-switch.tabs")

local M = {}

M.defaults = {
  root = nil, -- directory to list projects from; nil = Neovim's cwd
  depth = 3, -- how deep below the root to look
  hidden = false, -- include dot-directories
  ignore = { ".git", "node_modules", ".venv", "venv", "__pycache__", ".cache", "dist", "build", "target" },
  max = 5000, -- stop listing past this many directories
  git_only = true, -- start in "git repos" mode (toggle inside the picker)
  open_first = true, -- with no filter typed, list open projects first
  default_action = "tab", -- <CR> on a project that isn't open: "tab" (new tab) | "switch" (this tab)
  title = "Projects",
  width = 0.5, -- fraction of the editor (<=1) or columns (>1)
  height = 0.45, -- fraction of the editor (<=1) or rows (>1)
  on_open = nil, -- function(path) after a new tab is opened for a project
  on_switch = nil, -- function(path) after any tab is pointed at a project
  -- Tabs that are not projects. neo-herdr's herd tab is skipped by default;
  -- any tab with the `context_switch_ignore` tab variable is skipped too.
  ignore_tab = function(tab)
    local ok, v = pcall(vim.api.nvim_tabpage_get_var, tab, "neo_herdr")
    return ok and v ~= nil
  end,
  keys = { -- inside the picker (insert + normal mode; s/t/x/a also work in normal mode)
    accept = "<CR>", -- jump if open, else default_action
    switch = "<C-s>", -- point this tab at the project
    new_tab = "<C-t>", -- open the project in a new tab
    close = "<C-x>", -- close the project's tab, stay in the picker
    toggle = "<C-g>", -- git repos <-> all directories
    browse = "<Tab>", -- descend into the highlighted directory
    up = "<S-Tab>", -- browse the parent (also <BS> on an empty filter)
    cancel = "<Esc>",
  },
  keymaps = {
    open = "<leader>rp", -- false to skip
  },
}

M.config = vim.deepcopy(M.defaults)

-- ── Highlights ───────────────────────────────────────────────────────────────

local function hl(name)
  local ok, v = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and v or {}
end

--- Mix two 24-bit colours: `t` of `a` over `b`.
local function mix(a, b, t)
  local function ch(x, shift)
    return math.floor(x / 2 ^ shift) % 256
  end
  local out = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local v = math.floor(ch(a, shift) * t + ch(b, shift) * (1 - t) + 0.5)
    out = out + v * 2 ^ shift
  end
  return math.floor(out)
end

--- Open-project rows are tinted with an accent (DiffAdd's, else String's,
--- else green) mixed into the normal background, so the tint reads on any
--- colorscheme — including ones that style DiffAdd/Visual with `reverse`.
--- Everything else links into the colorscheme. All groups are `default`, so
--- a user's own :hi wins.
local function define_highlights()
  for name, target in pairs({
    ContextSwitchTitle = "Title",
    ContextSwitchKey = "Title",
    ContextSwitchMatch = "Title",
    ContextSwitchDim = "NonText",
    ContextSwitchSecondary = "Comment",
    ContextSwitchBorder = "NonText",
    ContextSwitchRoot = "Directory",
    ContextSwitchError = "DiagnosticError",
    ContextSwitchSelected = "Visual",
  }) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  local normal, add, str = hl("Normal"), hl("DiffAdd"), hl("String")
  local dark = vim.o.background ~= "light"
  local bg = normal.bg or (dark and 0x1c1c1c or 0xffffff)
  local accent = add.fg or str.fg or (dark and 0x5faf5f or 0x2e7d32)
  local cfg = add.ctermfg or str.ctermfg or (dark and 71 or 28)
  vim.api.nvim_set_hl(0, "ContextSwitchOpen", {
    fg = accent, bg = mix(accent, bg, 0.16), ctermfg = cfg, ctermbg = dark and 22 or 194, default = true,
  })
  vim.api.nvim_set_hl(0, "ContextSwitchOpenSelected", {
    fg = accent, bg = mix(accent, bg, 0.34), bold = true, ctermfg = cfg, ctermbg = dark and 28 or 157, default = true,
  })
  vim.api.nvim_set_hl(0, "ContextSwitchOpenLabel", { fg = accent, italic = true, ctermfg = cfg, default = true })
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Open the picker. `opts` overrides config for this call (e.g. { git_only = false }).
function M.open(opts)
  local o = vim.tbl_deep_extend("force", M.config, opts or {})
  return require("context-switch.picker").open(o)
end

--- Open `path` in a new tab (or jump to it if already open).
function M.new_tab(path)
  local p = tabs.norm(vim.fn.expand(path))
  local info = tabs.open_projects(M.config)[p]
  if info then
    tabs.jump(info.tabs[1])
  else
    tabs.open_new(p, M.config)
  end
end

--- Point the current tab at `path`.
function M.switch(path)
  tabs.switch_here(vim.fn.expand(path), M.config)
end

--- Close the tab(s) showing `path` (default: the current project).
function M.close(path)
  local p = path and tabs.norm(vim.fn.expand(path)) or tabs.current()
  local info = tabs.open_projects(M.config)[p]
  if not info then
    vim.notify("[context-switch] not open: " .. p, vim.log.levels.WARN)
    return false
  end
  for i = #info.tabs, 1, -1 do
    local ok, err = tabs.close(info.tabs[i])
    if not ok then
      vim.notify("[context-switch] " .. err, vim.log.levels.WARN)
      return false
    end
  end
  return true
end

--- Open projects: list of { path, tabs, current }, in tab order.
function M.projects()
  local out = {}
  for _, e in pairs(tabs.open_projects(M.config)) do
    out[#out + 1] = e
  end
  table.sort(out, function(a, b)
    return vim.api.nvim_tabpage_get_number(a.tabs[1]) < vim.api.nvim_tabpage_get_number(b.tabs[1])
  end)
  return out
end

M.current = tabs.current

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  define_highlights()
  local g = vim.api.nvim_create_augroup("context_switch", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = g, callback = define_highlights })

  vim.api.nvim_create_user_command("ContextSwitch", function(a)
    local o
    if a.args == "all" then
      o = { git_only = false }
    elseif a.args == "git" then
      o = { git_only = true }
    end
    M.open(o)
  end, {
    nargs = "?",
    complete = function()
      return { "git", "all" }
    end,
    desc = "context-switch: pick a project",
  })
  vim.api.nvim_create_user_command("ContextSwitchTab", function(a)
    M.new_tab(a.args)
  end, { nargs = 1, complete = "dir", desc = "context-switch: open a project in a new tab" })
  vim.api.nvim_create_user_command("ContextSwitchHere", function(a)
    M.switch(a.args)
  end, { nargs = 1, complete = "dir", desc = "context-switch: point this tab at a project" })
  vim.api.nvim_create_user_command("ContextSwitchClose", function(a)
    M.close(a.args ~= "" and a.args or nil)
  end, { nargs = "?", complete = "dir", desc = "context-switch: close a project's tab" })

  local km = M.config.keymaps or {}
  if km.open then
    vim.keymap.set("n", km.open, function()
      M.open()
    end, { desc = "context-switch: projects" })
  end
end

return M
