-- context-switch: directory scanning. Lists the directories under a root,
-- either every one (mode "all") or only git repositories (mode "git"). In git
-- mode a repository is listed but not descended into, so nested checkouts and
-- vendored trees don't flood the list.

local M = {}

local function basename(p)
  return p:match("([^/]+)/?$") or p
end
M.basename = basename

--- True when `dir` is the top of a git checkout: it holds a `.git` directory
--- (a normal clone) or a `.git` file (a worktree or submodule).
function M.is_repo(dir)
  return vim.uv.fs_stat(vim.fs.joinpath(dir, ".git")) ~= nil
end

--- Directories under `root` (relative paths) for `o.mode` ("git" | "all"),
--- sorted by depth then name. Returns list, truncated:boolean.
function M.scan(root, o)
  local ignore = {}
  for _, n in ipairs(o.ignore or {}) do
    ignore[n] = true
  end
  local git = o.mode ~= "all"
  local repo_cache = {}
  local function is_repo(rel)
    local v = repo_cache[rel]
    if v == nil then
      v = M.is_repo(vim.fs.joinpath(root, rel))
      repo_cache[rel] = v
    end
    return v
  end
  local function allowed(rel)
    local b = basename(rel)
    if ignore[b] then
      return false
    end
    if not o.hidden and b:sub(1, 1) == "." then
      return false
    end
    return true
  end
  local out, truncated = {}, false
  local ok = pcall(function()
    for name, t in vim.fs.dir(root, {
      depth = o.depth or 3,
      skip = function(rel)
        -- don't descend into ignored dirs, nor (in git mode) into a repo
        return allowed(rel) and not (git and is_repo(rel))
      end,
    }) do
      if t == "link" and allowed(name) then
        local st = vim.uv.fs_stat(vim.fs.joinpath(root, name))
        t = st and st.type or t
      end
      if t == "directory" and allowed(name) and (not git or is_repo(name)) then
        out[#out + 1] = name
        if #out >= (o.max or 5000) then
          truncated = true
          return
        end
      end
    end
  end)
  if not ok then
    return {}, false
  end
  table.sort(out, function(a, b)
    local da, db = select(2, a:gsub("/", "")), select(2, b:gsub("/", ""))
    if da ~= db then
      return da < db
    end
    return a < b
  end)
  return out, truncated
end

return M
