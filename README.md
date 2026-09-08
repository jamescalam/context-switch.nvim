# context-switch.nvim

Switch projects without leaving your seat. A project is a directory; the
picker lists the ones under your projects folder (git repositories by default),
shows which are already open in a tab, and lets you jump, switch, open or close
them from one floating window. Plain Neovim — floats, a prompt buffer,
`matchfuzzypos` — no picker plugin required.

```
╭ Projects ────────────────────────────────────────────╮
│ › ne                                             3/14 │
╰──────────────────────────────────────────────────────╯
╭ ~/projects  · git repos ─────────────────────────────╮
│ neo-herdr.nvim                               current │  ← open, on its own tint
│ neo-reviewr.nvim                               tab 2 │
│ agentengine                                          │
│ …                                                    │
╰──────────────────────────────────────────────────────╯
  ⏎ jump   ^s switch here   ^t new tab   ^x close tab   ^g all dirs   ⇥ browse   ⇧⇥ up   esc close
```

## How it decides what is "open"

Nothing is bookkept. A project is open when some tab's working directory
(`:tcd`, or the global cwd for tabs without one) is that directory — so tabs
you opened by hand with `:tabnew | tcd …` count, and closing a tab any way
you like takes the project off the list. neo-herdr's herd tab is skipped, as
is any tab carrying a `context_switch_ignore` tab variable (`ignore_tab` is
configurable).

## Requirements

Neovim 0.10+.

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jamescalam/context-switch.nvim",
  lazy = false,
  config = function()
    require("context-switch").setup({ root = "~/projects" })
  end,
}
```

Pin a tag with `version = "v0.x"` if you prefer tagged releases to `main`.
For a local checkout while hacking on it, swap the first line for
`dir = "~/path/to/context-switch.nvim", name = "context-switch",`.

`<leader>rp` opens the picker; `:ContextSwitch` does too (`:ContextSwitch all`
starts in all-directories mode).

## Inside the picker

The prompt holds a path. Everything up to its last `/` is the directory being
browsed (relative to the root, or absolute / `~`); what follows filters the
list fuzzily. `../` browses the parent, `apps/` a child, `~/code/` anywhere.

| Key                     | Action                                                         |
| ----------------------- | -------------------------------------------------------------- |
| `⏎`                     | Open project: jump to its tab. Otherwise: open a new tab (`default_action`) |
| `^s` (`s`)              | Point **this** tab at the project (`:tcd`)                      |
| `^t` (`t`)              | Open the project in a **new** tab, even if it is open elsewhere |
| `^x` (`x`)              | Close the project's tab — the picker stays open                 |
| `^g` (`a`)              | Toggle git repos ↔ all directories                              |
| `⇥` / `→`               | Browse into the highlighted directory                           |
| `⇧⇥`, `⌫` on empty      | Browse the parent directory                                     |
| `^n`/`^p`, `↓`/`↑`, `j`/`k` | Move                                                        |
| `esc`, `^c`, `q`        | Close                                                           |

Letters in parentheses are normal-mode aliases (`<C-\><C-n>` leaves the
prompt's insert mode; `esc` closes from either mode).
The bar under the list always shows what applies to the highlighted row.

Open projects are drawn on the `ContextSwitchOpen` background with the tab
number on the right (`current` for the tab you are in). With nothing typed
they float to the top of the list. Closing the tab you are currently in from
inside the picker works too: the picker reopens itself in the tab that takes
its place, with your filter intact.

## Configuration (defaults)

```lua
require("context-switch").setup({
  root = nil,             -- directory to list projects from; nil = Neovim's cwd
  depth = 3,              -- how deep below the root to look
  hidden = false,         -- include dot-directories
  ignore = { ".git", "node_modules", ".venv", "venv", "__pycache__", ".cache", "dist", "build", "target" },
  max = 5000,
  git_only = true,        -- start in "git repos" mode (toggle inside the picker)
  open_first = true,      -- with no filter typed, list open projects first
  default_action = "tab", -- <CR> on a project that isn't open: "tab" | "switch"
  title = "Projects",
  width = 0.5,            -- fraction of the editor (<=1) or columns (>1)
  height = 0.45,
  on_open = nil,          -- function(path): runs after a new project tab opens
  on_switch = nil,        -- function(path): runs after any tab is pointed at a project
  ignore_tab = function(tab) ... end, -- default: skip neo-herdr's herd tab
  keys = { accept = "<CR>", switch = "<C-s>", new_tab = "<C-t>", close = "<C-x>",
           toggle = "<C-g>", browse = "<Tab>", up = "<S-Tab>", cancel = "<Esc>" },
  keymaps = { open = "<leader>rp" }, -- false to skip
})
```

A new project tab starts with an empty buffer. To land in a file tree instead:

```lua
on_open = function(path) vim.cmd("Neotree " .. vim.fn.fnameescape(path)) end,
```

If `<C-s>` never reaches Neovim, your terminal is using it for flow control;
`stty -ixon` in your shell rc frees it, or pick another key in `keys.switch`.

## API

```lua
local cs = require("context-switch")
cs.open({ git_only = false })   -- picker, with per-call overrides
cs.new_tab("~/code/acta")       -- open in a new tab (or jump if open)
cs.switch("~/code/acta")        -- point this tab at it
cs.close()                      -- close the current project's tab(s)
cs.projects()                   -- { { path, tabs, current }, ... } in tab order
cs.current()                    -- the current tab's project path
```

Commands: `:ContextSwitch [git|all]`, `:ContextSwitchTab {dir}`,
`:ContextSwitchHere {dir}`, `:ContextSwitchClose [dir]`.

## Highlights

`ContextSwitchOpen` (open rows, links to `DiffAdd`), `ContextSwitchOpenSelected`
(the highlighted open row), `ContextSwitchOpenLabel` (the `tab N` marker),
`ContextSwitchSelected` (`Visual`), `ContextSwitchTitle`, `ContextSwitchKey`,
`ContextSwitchMatch` (`Title`), `ContextSwitchRoot` (`Directory`),
`ContextSwitchSecondary` (`Comment`), `ContextSwitchDim`, `ContextSwitchBorder`
(`NonText`), `ContextSwitchError`. All are defined with `default = true`, so
your own `:hi` wins.

## Health

`:checkhealth context-switch` reports the Neovim version, the root and how many
repos it holds, and how many projects are open.
