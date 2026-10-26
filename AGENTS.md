# AGENTS.md

## What this repo is

A Neovim plugin (`render-markdown-mermaid.nvim`) that renders fenced `mermaid` code blocks inline using `render-markdown.nvim` and `bm` (Beautiful Mermaid), `termaid`, or `mermaid-ascii` as the CLI backend.

## Key architecture

- **Entrypoint**: `lua/render-markdown-mermaid/init.lua` — `M.setup(opts)` is the only public API. Users call it via lazy.nvim `opts = {}`. The plugin guard in `plugin/render-markdown-mermaid.lua` does NOT call setup.
- **Rendering pipeline**: `display.lua` (treesitter query → cache check → async `vim.system()` call) → `renderer.lua` (builds CLI args for `bm`, `termaid`, `mermaid-ascii` (upstream or pgavlin's fork), `selkie`, or `merman-cli`) → result placed as extmark virtual lines.
- **Inline navigation**: `scroll.lua` owns per-fence view state. Focus opens a borderless read-only scratch buffer over the inline preview, so normal Vim motions/search/selection work without movement-key overrides. `display.lua` supplies cached output and an extmark redraw callback; navigation never invokes the renderer. Inactive virtual lines are shared between source windows and fit the smallest window.
- **Activation shortcut**: `navigation.lua` installs the buffer-local `focus_key` (Enter by default) in Markdown/MDX. It opens navigation only at rendered fences/preview anchors; a private Plug mapping delegates all other presses to the original mapping with native callback/expr/remap semantics. Disabling/changing the shortcut restores existing mappings and respects later user overrides.
- **Cache**: `cache.lua` keys on `sha256(json({source, cmd, mode, cli, width}))`.
- **Config resolution**: `config.lua` — `cmd` auto-resolves to first available of `['selkie', 'bm', 'termaid', 'mermaid-ascii']` (`mode = 'ascii'` prefers ASCII-capable backends: `bm`, `termaid`, `mermaid-ascii`); `merman-cli` is opt-in via `cmd` and never auto-selected; `mode` defaults to `'unicode'`; `placement` defaults to `'above'`; `width` defaults to `'auto'` when `merman-cli` is selected (window-width fitting, and the only renderer that consumes it).

## Testing

Run `nvim --headless -u NONE -l tests/scroll_spec.lua` for native cursor motions/search/yank and viewer lifecycle, and `nvim --headless -u NONE -l tests/enter_spec.lua` for activation and Enter fallback/mapping preservation. Both need the Markdown treesitter parser but stub CLI output. There is no CI, Makefile, linter config, or formatter config.

## Smoke test

Open `samples/tall.md` or `samples/sequence_diagrams.md` in Neovim. For scrolling, place the cursor on the tall fence, press Enter, navigate, and exit with `q`/`Esc`. Run `:checkhealth render-markdown-mermaid` to verify dependencies.

## Requirements to verify behavior

- Neovim 0.10+
- `bm` (`beautiful-mermaid`), `termaid`, or `mermaid-ascii` in `PATH`
- `nvim-treesitter` with `markdown` and `markdown_inline` parsers installed (`:TSInstall markdown markdown_inline`)
- `render-markdown.nvim` installed

## Treesitter query

`display.lua` parses `markdown` using an inline treesitter query — the `queries/markdown/` directory is intentionally empty (no bundled queries files). The query is defined as a string literal in `display.lua`.

## Public API surface

Only `require('render-markdown-mermaid').setup(opts)` is a public Lua interface. The `M.config` field is set after setup. Setup registers `:MermaidFocus` and a context-sensitive `focus_key` in Markdown/MDX. Only `q`/`Esc` are mapped in the temporary viewer buffer, which is wiped on exit; source movement keys are untouched.

## `autoload/health/` is empty

Health check is implemented in `lua/render-markdown-mermaid/health.lua` via the Lua health API, not the legacy Vimscript `autoload/health/` pattern. The empty directory can be ignored.
