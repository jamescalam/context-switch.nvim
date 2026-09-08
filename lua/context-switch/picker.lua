-- context-switch: the floating project picker. A one-line path prompt over a
-- fuzzy-filtered list of projects, with a keybinding bar underneath. Plain
-- Neovim (floats, a prompt buffer, matchfuzzypos); no picker plugin.
--
-- The prompt holds a path. Everything up to its last `/` is the directory
-- being browsed (relative to the root, or absolute / `~`); what follows the
-- last `/` filters the list. So `../` browses the parent, `apps/` a child.
--
-- Projects already open in a tab are drawn on their own background with the
-- tab number at the right; picking one jumps to that tab instead of opening
-- it again. The other actions (switch this tab, open a new tab, close a
-- project's tab) never leave the picker unless they change what you're
-- looking at. The bar under the list always shows what applies to the
-- highlighted row.

local scan = require("context-switch.scan")
local tabs = require("context-switch.tabs")

local M = {}

local NS = vim.api.nvim_create_namespace("context_switch_picker")
local AUG = "context_switch_picker"
local PROMPT = "› "
local SELF = "." -- the row that means "the browsed directory itself"
local MARGIN = " " -- left margin inside the list

-- ── Paths ────────────────────────────────────────────────────────────────────

local basename = scan.basename

--- Split a prompt into the directory part (ending in `/`, or "") and the
--- filter fragment after it.
local function split_prompt(text)
  local dir, frag = text:match("^(.*/)([^/]*)$")
  if not dir then
    return "", text
  end
  return dir, frag
end

--- Absolute directory a prompt's directory part points at, relative to `base`.
local function resolve(base, dir)
  local p
  if dir == "" then
    p = base
  elseif dir:sub(1, 1) == "/" or dir:sub(1, 1) == "~" then
    p = dir
  else
    p = vim.fs.joinpath(base, dir)
  end
  return tabs.norm(p)
end

--- Directory part with its last component removed.
local function parent_dir(dir)
  if dir:match("^/+$") then
    return "/"
  end
  local trimmed = dir:gsub("/+$", "")
  local last = basename(trimmed)
  if trimmed == "" or trimmed == "~" or last == ".." or last == "." then
    return dir .. "../"
  end
  return trimmed:match("^(.*/)[^/]+$") or ""
end

local function tilde(p)
  return vim.fn.fnamemodify(p, ":~")
end

-- ── Filtering ────────────────────────────────────────────────────────────────

--- Filter `items` by `query`. Returns list of { text, cols } where cols are
--- 0-based byte columns of the matched characters (empty for no query).
local function filter(items, query, with_self)
  local res = {}
  if query == "" then
    if with_self then
      res[1] = { text = SELF, cols = {} }
    end
    for _, it in ipairs(items) do
      res[#res + 1] = { text = it, cols = {} }
    end
    return res
  end
  local m = vim.fn.matchfuzzypos(items, query)
  for i, text in ipairs(m[1]) do
    local cols = {}
    for _, ci in ipairs(m[2][i] or {}) do
      cols[#cols + 1] = vim.str_byteindex(text, ci)
    end
    res[#res + 1] = { text = text, cols = cols }
  end
  return res
end

-- ── Key labels for the bar ───────────────────────────────────────────────────

local PRETTY = {
  ["<cr>"] = "⏎",
  ["<tab>"] = "⇥",
  ["<s-tab>"] = "⇧⇥",
  ["<bs>"] = "⌫",
  ["<esc>"] = "esc",
  ["<space>"] = "␣",
}

local function pretty(lhs)
  local l = lhs:lower()
  if PRETTY[l] then
    return PRETTY[l]
  end
  local ctrl = l:match("^<c%-(.)>$")
  if ctrl then
    return "^" .. ctrl
  end
  return lhs
end

-- ── Picker ───────────────────────────────────────────────────────────────────

local Picker = {}
Picker.__index = Picker

function Picker:geometry()
  local cols, lines = vim.o.columns, vim.o.lines
  local o = self.opts
  local function dim(v, total)
    return v <= 1 and math.floor(total * v) or v
  end
  local width = math.max(44, math.min(dim(o.width or 0.5, cols), cols - 4))
  local list_h = math.max(5, math.min(dim(o.height or 0.45, lines), lines - 9))
  local total = list_h + 7 -- prompt(3) + list(list_h + 2) + bar(up to 2)
  local row = math.max(0, math.floor((lines - total) / 2))
  local col = math.floor((cols - width) / 2)
  return width, list_h, row, col
end

function Picker:open_windows()
  local width, list_h, row, col = self:geometry()

  self.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.list_buf].bufhidden = "wipe"
  vim.bo[self.list_buf].buftype = "nofile"
  vim.bo[self.list_buf].filetype = "context-switch"
  self.list_win = vim.api.nvim_open_win(self.list_buf, false, {
    relative = "editor",
    row = row + 3,
    col = col,
    width = width,
    height = list_h,
    style = "minimal",
    border = "rounded",
    zindex = 60,
    noautocmd = true,
  })
  vim.wo[self.list_win].winhighlight = "NormalFloat:Normal,FloatBorder:ContextSwitchBorder,FloatTitle:ContextSwitchRoot"
  vim.wo[self.list_win].cursorline = false
  vim.wo[self.list_win].wrap = false
  vim.wo[self.list_win].scrolloff = 2

  self.bar_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.bar_buf].bufhidden = "wipe"
  vim.bo[self.bar_buf].buftype = "nofile"
  self.bar_win = vim.api.nvim_open_win(self.bar_buf, false, {
    relative = "editor",
    row = row + list_h + 5,
    col = col,
    width = width + 2,
    height = 1,
    style = "minimal",
    border = "none",
    focusable = false,
    zindex = 60,
    noautocmd = true,
  })
  vim.wo[self.bar_win].winhighlight = "NormalFloat:Normal"

  self.prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.prompt_buf].bufhidden = "wipe"
  vim.bo[self.prompt_buf].buftype = "prompt"
  vim.bo[self.prompt_buf].filetype = "context-switch-prompt"
  vim.fn.prompt_setprompt(self.prompt_buf, PROMPT)
  self.prompt_win = vim.api.nvim_open_win(self.prompt_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = { { " " .. self.title .. " ", "ContextSwitchTitle" } },
    title_pos = "left",
    zindex = 61,
    noautocmd = true,
  })
  vim.wo[self.prompt_win].winhighlight = "NormalFloat:Normal,FloatBorder:ContextSwitchBorder"
end

function Picker:relayout()
  local width, list_h, row, col = self:geometry()
  pcall(vim.api.nvim_win_set_config, self.prompt_win, { relative = "editor", row = row, col = col, width = width, height = 1 })
  pcall(vim.api.nvim_win_set_config, self.list_win, { relative = "editor", row = row + 3, col = col, width = width, height = list_h })
  pcall(vim.api.nvim_win_set_config, self.bar_win, { relative = "editor", row = row + list_h + 5, col = col, width = width + 2, height = 1 })
  self:render_bar()
end

function Picker:text()
  if not (self.prompt_buf and vim.api.nvim_buf_is_valid(self.prompt_buf)) then
    return ""
  end
  local line = vim.api.nvim_buf_get_lines(self.prompt_buf, -2, -1, false)[1] or ""
  return line:sub(#PROMPT + 1)
end

function Picker:set_text(text)
  vim.api.nvim_buf_set_lines(self.prompt_buf, 0, -1, false, { PROMPT .. text })
  vim.api.nvim_win_set_cursor(self.prompt_win, { 1, #PROMPT + #text })
  self:sync()
end

function Picker:refresh_open()
  self.open = tabs.open_projects(self.opts)
end

function Picker:rescan()
  self.valid = vim.fn.isdirectory(self.root) == 1
  local o = vim.tbl_extend("force", self.opts, { mode = self.mode })
  self.items, self.truncated = self.valid and scan.scan(self.root, o) or {}, false
  -- the browsed directory itself is offered when it qualifies
  self.with_self = self.valid and (self.mode == "all" or scan.is_repo(self.root))
  self:set_list_title()
end

function Picker:set_list_title()
  if not (self.list_win and vim.api.nvim_win_is_valid(self.list_win)) then
    return
  end
  local label
  if self.valid then
    label = " " .. tilde(self.root) .. "  · " .. (self.mode == "git" and "git repos" or "all dirs")
      .. (self.truncated and ("  (first " .. #self.items .. ")") or "") .. " "
  else
    label = " " .. tilde(self.root) .. "  · not a directory "
  end
  vim.api.nvim_win_set_config(self.list_win, {
    title = { { label, self.valid and "ContextSwitchRoot" or "ContextSwitchError" } },
    title_pos = "left",
  })
end

--- Re-derive the browsed directory from the prompt, rescan if it changed,
--- and redraw. Called on every prompt change.
function Picker:sync()
  local dir, frag = split_prompt(self:text())
  local root = resolve(self.base, dir)
  if root ~= self.root then
    self.root = root
    self:rescan()
    self.sel = 1
  end
  if frag ~= self.frag then
    self.sel = 1
  end
  self.frag = frag
  self:render()
end

function Picker:toggle_mode()
  self.mode = self.mode == "git" and "all" or "git"
  local keep = self:selected_path()
  self:rescan()
  self:render()
  self:select_path(keep)
end

--- Absolute path a row stands for.
function Picker:row_path(r)
  if r.text == SELF then
    return self.root
  end
  return vim.fs.joinpath(self.root, r.text)
end

--- Open-project info for a row, or nil.
function Picker:row_open(r)
  return r and self.open[self:row_path(r)] or nil
end

function Picker:render()
  self.rows = self.valid and filter(self.items, self.frag, self.with_self) or {}
  -- with no filter, open projects float to the top (stable)
  if self.frag == "" and self.opts.open_first ~= false and #self.rows > 1 then
    local open, rest = {}, {}
    for _, r in ipairs(self.rows) do
      if self:row_open(r) then
        open[#open + 1] = r
      else
        rest[#rest + 1] = r
      end
    end
    vim.list_extend(open, rest)
    self.rows = open
  end
  local lines = {}
  for i, r in ipairs(self.rows) do
    lines[i] = MARGIN .. (r.text == SELF and ("./  " .. basename(self.root)) or r.text)
  end
  if #lines == 0 then
    if not self.valid then
      lines[1] = MARGIN .. "not a directory"
    elseif self.mode == "git" and #self.items == 0 and self.frag == "" then
      lines[1] = MARGIN .. "no git repos here  ·  " .. pretty(self.opts.keys.toggle) .. " shows all directories"
    else
      lines[1] = MARGIN .. "no matches"
    end
  end
  vim.bo[self.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.list_buf, 0, -1, false, lines)
  vim.bo[self.list_buf].modifiable = false
  self.lines = lines
  self.sel = math.max(1, math.min(self.sel or 1, #self.rows))
  self:paint()
  -- count, right-aligned on the prompt line
  vim.api.nvim_buf_clear_namespace(self.prompt_buf, NS, 0, -1)
  local total = #self.items + (self.with_self and 1 or 0)
  pcall(vim.api.nvim_buf_set_extmark, self.prompt_buf, NS, 0, 0, {
    virt_text = { { string.format("%d/%d ", #self.rows, total), "ContextSwitchDim" } },
    virt_text_pos = "right_align",
  })
end

--- Row highlights: dim parents, bright leaf, fuzzy matches, open-project rows
--- and the selection. Cheap enough to redo on every move.
function Picker:paint()
  local buf = self.list_buf
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  if #self.rows == 0 then
    vim.api.nvim_buf_set_extmark(buf, NS, 0, 0, { end_col = #self.lines[1], hl_group = "ContextSwitchDim" })
    return
  end
  local off = #MARGIN
  for i, r in ipairs(self.rows) do
    local l = i - 1
    local info = self:row_open(r)
    local selected = i == self.sel
    local line_hl
    if info and selected then
      line_hl = "ContextSwitchOpenSelected"
    elseif info then
      line_hl = "ContextSwitchOpen"
    elseif selected then
      line_hl = "ContextSwitchSelected"
    end
    if line_hl then
      vim.api.nvim_buf_set_extmark(buf, NS, l, 0, { line_hl_group = line_hl, priority = 10 })
    end
    if r.text == SELF then
      vim.api.nvim_buf_set_extmark(buf, NS, l, off, { end_col = off + 4, hl_group = "ContextSwitchSecondary" })
    else
      local leaf_start = #r.text - #basename(r.text)
      if leaf_start > 0 then
        vim.api.nvim_buf_set_extmark(buf, NS, l, off, { end_col = off + leaf_start, hl_group = "ContextSwitchSecondary" })
      end
      for _, c in ipairs(r.cols) do
        vim.api.nvim_buf_set_extmark(buf, NS, l, off + c, { end_col = off + c + 1, hl_group = "ContextSwitchMatch" })
      end
    end
    if info then
      local label
      if info.current then
        label = "current"
      else
        local nrs = {}
        for _, t in ipairs(info.tabs) do
          nrs[#nrs + 1] = vim.api.nvim_tabpage_get_number(t)
        end
        label = "tab " .. table.concat(nrs, ",")
      end
      vim.api.nvim_buf_set_extmark(buf, NS, l, 0, {
        virt_text = { { label .. " ", "ContextSwitchOpenLabel" } },
        virt_text_pos = "right_align",
      })
    end
  end
  pcall(vim.api.nvim_win_set_cursor, self.list_win, { self.sel, 0 })
  self:render_bar()
end

--- The keybinding bar: only what applies to the highlighted row.
function Picker:render_bar()
  if not (self.bar_buf and vim.api.nvim_buf_is_valid(self.bar_buf)) then
    return
  end
  local K = self.opts.keys
  local r = self.rows[self.sel]
  local info = self:row_open(r)
  local items = {}
  local function add(key, desc)
    items[#items + 1] = { pretty(key), desc }
  end
  if info then
    add(K.accept, "jump")
    add(K.switch, "switch here")
    add(K.new_tab, "new tab")
    add(K.close, "close tab")
  elseif r then
    if self.opts.default_action == "switch" then
      add(K.accept, "switch here")
      add(K.new_tab, "new tab")
    else
      add(K.accept, "open tab")
      add(K.switch, "switch here")
    end
  end
  add(K.toggle, self.mode == "git" and "all dirs" or "git only")
  add(K.browse, "browse")
  add(K.up, "up")
  add(K.cancel, "close")

  -- lay the items out left to right, spilling onto a second line if needed
  local width = vim.api.nvim_win_get_width(self.bar_win)
  local rows, marks = { " " }, {}
  local li = 1
  for _, it in ipairs(items) do
    local key, desc = it[1], it[2]
    local seg = key .. " " .. desc
    local sep = #rows[li] > 1 and "   " or ""
    if vim.fn.strdisplaywidth(rows[li] .. sep .. seg) > width then
      if li >= 2 then
        break
      end
      li, sep = li + 1, ""
      rows[li] = " "
    end
    local col = #rows[li] + #sep
    rows[li] = rows[li] .. sep .. seg
    marks[#marks + 1] = { li - 1, col, col + #key, "ContextSwitchKey" }
    marks[#marks + 1] = { li - 1, col + #key + 1, col + #seg, "ContextSwitchDim" }
  end
  if vim.api.nvim_win_get_height(self.bar_win) ~= #rows then
    pcall(vim.api.nvim_win_set_config, self.bar_win, { height = #rows })
  end
  vim.bo[self.bar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.bar_buf, 0, -1, false, rows)
  vim.bo[self.bar_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(self.bar_buf, NS, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(self.bar_buf, NS, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
end

function Picker:move(delta)
  if #self.rows == 0 then
    return
  end
  self.sel = ((self.sel - 1 + delta) % #self.rows) + 1
  self:paint()
end

function Picker:select_path(path)
  if not path then
    return
  end
  for i, r in ipairs(self.rows) do
    if self:row_path(r) == path then
      self.sel = i
      self:paint()
      return
    end
  end
end

--- Absolute path of the selected row, or nil.
function Picker:selected_path()
  local r = self.rows[self.sel]
  if not r or not self.valid then
    return nil
  end
  return self:row_path(r)
end

--- The whole prompt as a path, if it names an existing directory.
function Picker:typed_dir()
  local t = self:text()
  if t == "" then
    return nil
  end
  local p = resolve(self.base, t)
  if vim.fn.isdirectory(p) == 1 then
    return p
  end
  return nil
end

--- Path an action applies to: the selection, else a typed directory.
function Picker:target()
  return self:selected_path() or self:typed_dir()
end

--- <Tab>: put the selection into the prompt as a directory to browse.
function Picker:browse()
  local r = self.rows[self.sel]
  if not r or not self.valid then
    return
  end
  local dir = split_prompt(self:text())
  if r.text == SELF then
    if dir ~= self:text() then
      self:set_text(dir)
    end
    return
  end
  self:set_text(dir .. r.text .. "/")
end

--- <S-Tab> / <BS> on an empty filter: browse the parent directory.
function Picker:up()
  local dir = split_prompt(self:text())
  local from = self.root
  self:set_text(parent_dir(dir))
  self:select_path(from)
end

-- ── Actions ──────────────────────────────────────────────────────────────────

local function notify(msg, level)
  vim.notify("[context-switch] " .. msg, level or vim.log.levels.INFO)
end

--- Close the picker, then run `fn` from the window we came from.
function Picker:finish(fn)
  self:close()
  fn()
end

function Picker:accept()
  local p = self:target()
  if not p then
    return
  end
  local info = self.open[p]
  if info then
    self:finish(function()
      tabs.jump(info.tabs[1])
    end)
  elseif self.opts.default_action == "switch" then
    self:switch_here()
  else
    self:new_tab()
  end
end

function Picker:switch_here()
  local p = self:target()
  if not p then
    return
  end
  local opts = self.opts
  self:finish(function()
    tabs.switch_here(p, opts)
  end)
end

function Picker:new_tab()
  local p = self:target()
  if not p then
    return
  end
  local opts = self.opts
  self:finish(function()
    tabs.open_new(p, opts)
  end)
end

--- Close the highlighted project's tab and stay in the picker. Closing the
--- tab we are floating in takes the picker with it, so that case reopens the
--- picker where it was.
function Picker:close_tab()
  local p = self:target()
  local info = p and self.open[p]
  if not info then
    notify("not open in any tab")
    return
  end
  local tab = info.tabs[1]
  if tab == vim.api.nvim_get_current_tabpage() then
    local snap = self:snapshot()
    local opts = self.opts
    self:close()
    local ok, err = tabs.close(tab)
    if not ok then
      notify(err, vim.log.levels.WARN)
    end
    -- we are inside a mapping: (stop|start)insert only apply once it returns
    vim.schedule(function()
      M.open(opts, snap)
    end)
    return
  end
  local ok, err = tabs.close(tab)
  if not ok then
    notify(err, vim.log.levels.WARN)
    return
  end
  self:refresh_open()
  self:render()
  self:select_path(p)
end

function Picker:snapshot()
  return { text = self:text(), mode = self.mode, path = self:selected_path() }
end

function Picker:close()
  if self.closed then
    return
  end
  self.closed = true
  pcall(vim.api.nvim_del_augroup_by_name, AUG)
  vim.cmd("stopinsert")
  for _, w in ipairs({ self.prompt_win, self.list_win, self.bar_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  if self.prev_win and vim.api.nvim_win_is_valid(self.prev_win) then
    pcall(vim.api.nvim_set_current_win, self.prev_win)
  end
  M.current = nil
end

function Picker:cancel()
  if not self.closed then
    self:close()
  end
end

function Picker:install_keys()
  local b = self.prompt_buf
  local K = self.opts.keys
  local function map(modes, lhs, fn)
    if lhs and lhs ~= "" then
      vim.keymap.set(modes, lhs, fn, { buffer = b, nowait = true, silent = true })
    end
  end
  local both = { "i", "n" }
  map(both, K.accept, function()
    self:accept()
  end)
  map(both, K.switch, function()
    self:switch_here()
  end)
  map(both, K.new_tab, function()
    self:new_tab()
  end)
  map(both, K.close, function()
    self:close_tab()
  end)
  map(both, K.toggle, function()
    self:toggle_mode()
  end)
  map(both, K.cancel, function()
    self:cancel()
  end)
  map(both, "<C-c>", function()
    self:cancel()
  end)
  for _, k in ipairs({ "q", "<Esc>" }) do
    map("n", k, function()
      self:cancel()
    end)
  end
  for _, k in ipairs({ "<C-n>", "<Down>", "<C-j>" }) do
    map(both, k, function()
      self:move(1)
    end)
  end
  for _, k in ipairs({ "<C-p>", "<Up>", "<C-k>" }) do
    map(both, k, function()
      self:move(-1)
    end)
  end
  map("n", "j", function()
    self:move(1)
  end)
  map("n", "k", function()
    self:move(-1)
  end)
  -- single-letter normal-mode aliases for the actions
  map("n", "s", function()
    self:switch_here()
  end)
  map("n", "t", function()
    self:new_tab()
  end)
  map("n", "x", function()
    self:close_tab()
  end)
  map("n", "a", function()
    self:toggle_mode()
  end)
  for _, k in ipairs({ K.browse, "<Right>", "<C-l>" }) do
    map(both, k, function()
      self:browse()
    end)
  end
  map(both, K.up, function()
    self:up()
  end)
  -- <BS> with nothing to filter goes up a directory; otherwise it is a
  -- backspace. (expr mappings run under textlock, so up() is scheduled.)
  for _, k in ipairs({ "<BS>", "<C-h>" }) do
    vim.keymap.set("i", k, function()
      local _, frag = split_prompt(self:text())
      if frag == "" then
        vim.schedule(function()
          if not self.closed then
            self:up()
          end
        end)
        return ""
      end
      return "<BS>"
    end, { buffer = b, expr = true, nowait = true, silent = true })
  end

  local g = vim.api.nvim_create_augroup(AUG, { clear = true })
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = g,
    buffer = b,
    callback = function()
      self:sync()
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = g,
    buffer = b,
    callback = function()
      vim.schedule(function()
        if not self.closed and vim.api.nvim_get_current_win() ~= self.prompt_win then
          self:cancel()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = g,
    callback = function()
      if not self.closed then
        self:relayout()
      end
    end,
  })
end

--- Open the picker with resolved config `opts`; `restore` (optional) is a
--- snapshot from a previous instance to pick up where it left off.
function M.open(opts, restore)
  if M.current and not M.current.closed then
    M.current:cancel()
  end
  local base = resolve(vim.fn.getcwd(), opts.root and vim.fn.expand(opts.root) or "")
  if vim.fn.isdirectory(base) ~= 1 then
    base = tabs.norm(vim.fn.getcwd())
  end
  local self = setmetatable({
    opts = opts,
    title = opts.title or "Projects",
    prev_win = vim.api.nvim_get_current_win(),
    base = base,
    mode = (restore and restore.mode) or (opts.git_only == false and "all" or "git"),
    sel = 1,
    rows = {},
    lines = {},
    frag = "",
  }, Picker)
  M.current = self
  self:refresh_open()
  self:open_windows()
  self:install_keys()
  if restore and restore.text ~= "" then
    self:set_text(restore.text)
  else
    self:sync()
  end
  if restore then
    self:select_path(restore.path)
  end
  vim.cmd("startinsert!")
  return self
end

-- exposed for tests
M._filter = filter
M._split = split_prompt
M._resolve = resolve
M._parent_dir = parent_dir
M._pretty = pretty

return M
