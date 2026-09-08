local M = {}

function M.check()
  local h = vim.health
  h.start("context-switch.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim 0.10+ required (vim.fs.dir, vim.uv, prompt buffers)")
  end
  local cfg = require("context-switch").config
  local root = cfg.root and vim.fn.expand(cfg.root) or vim.fn.getcwd()
  if vim.fn.isdirectory(root) == 1 then
    local repos = require("context-switch.scan").scan(root, vim.tbl_extend("force", cfg, { mode = "git" }))
    h.ok(string.format("root %s (%d git repos within depth %d)", vim.fn.fnamemodify(root, ":~"), #repos, cfg.depth))
    if #repos == 0 then
      h.warn("no git repos under the root; set `root` to your projects folder or raise `depth`")
    end
  else
    h.error("root is not a directory: " .. root)
  end
  local n = 0
  for _ in pairs(require("context-switch.tabs").open_projects(cfg)) do
    n = n + 1
  end
  h.info(n .. " project(s) open in tabs")
end

return M
