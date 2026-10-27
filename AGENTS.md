# AGENTS.md

## What this repo is

A Neovim plugin (`render-markdown-mermaid.nvim`) that renders fenced `mermaid` code blocks inline using `render-markdown.nvim` and `bm` (Beautiful Mermaid), `termaid`, or `mermaid-ascii` as the CLI backend.

## Key architecture

- **Entrypoint**: `lua/render-markdown-mermaid/init.lua` — `M.setup(opts)` is the only public API. Users call it via lazy.nvim `opts = {}`. The plugin guard in `plugin/render-markdown-mermaid.lua` does NOT call setup.
- **Rendering pipeline**: `display.lua` (treesitter query → cache check → async `vim.system()` call) → `renderer.lua` (builds CLI args for `bm`, `termaid`, `mermaid-ascii` (upstream or pgavlin's fork), `selkie`, or `merman-cli`) → result placed as extmark virtual lines.
- **Inline navigation**: `scroll.lua` owns per-fence view state. Focus opens a borderless read-only scratch buffer over the inline preview, so normal Vim motions/search/selection work without movement-key overrides. `display.lua` supplies cached output and an extmark redraw callback; navigation never invokes the renderer. Inactive virtual lines are shared between source windows and fit the smallest window.
- **Preview layout**: `max_preview_lines = '75%'` is relative to source-window height; positive integers retain fixed-row behavior and `false` disables the inactive cap. `center = true` adds display-only horizontal padding based on full-output display-cell width; the focused window uses the same offset without changing its buffer text.
- **Activation shortcut**: `navigation.lua` installs the buffer-local `focus_key` (Enter by default) in Markdown/MDX. It opens navigation only at rendered fences/preview anchors; a private Plug mapping delegates all other presses to the original mapping with native callback/expr/remap semantics. Disabling/changing the shortcut restores existing mappings and respects later user overrides.
- **Renderer cycling**: `:MermaidCycle[!]` changes the session-wide backend, skipping missing executables. Tab/Shift-Tab keeps the same viewer open and swaps complete results in place. Prior frames remain visible while rendering; `scroll.finish()` aligns once after the full display pass. Concealment uses the original source cursor, not its parked anchor. `display.lua` guards superseded callbacks while still caching their results.
- **Cache**: `cache.lua` keys on `sha256(json({source, cmd, mode, cli, width}))`.
- **Config resolution**: `config.lua` — `cmd` auto-resolves to first available of `['selkie', 'bm', 'termaid', 'mermaid-ascii']` (`mode = 'ascii'` prefers ASCII-capable backends: `bm`, `termaid`, `mermaid-ascii`); `merman-cli` is opt-in via `cmd` and never auto-selected; `mode` defaults to `'unicode'`; `placement` defaults to `'above'`; `width` defaults to `'auto'` when `merman-cli` is selected (window-width fitting, and the only renderer that consumes it).

## Testing

Run `nvim --headless -u NONE -l tests/scroll_spec.lua` for native cursor motions/search/yank and viewer lifecycle, and `nvim --headless -u NONE -l tests/enter_spec.lua` for activation and Enter fallback/mapping preservation. Both need the Markdown treesitter parser but stub CLI output. There is no CI, Makefile, linter config, or formatter config.

Layout tests: `nvim --headless -u NONE -l tests/preview_height_spec.lua` (percentage validation, resizing, split limits) and `nvim --headless -u NONE -l tests/center_spec.lua` (Unicode/gutters, alignment, overflow, and unpadded focus text).

Cycling tests: `nvim --headless -u NONE -l tests/cycle_spec.lua` checks selection/wrapping, availability, Tab navigation, command preservation, widths, cache reuse, and late callbacks. `tests/cycle_stability_spec.lua` covers retained frames, stable viewer identity, and rapid switching. Run `nvim -u NONE -c 'luafile tests/cycle_layout_spec.lua'` in a real terminal for pending-frame screen equality with treesitter/concealment and multiple fences; `MERMAID_TEST_SCROLLOFF=8` exercises source margins.

For background regressions, run `nvim -u NONE -c 'luafile tests/background_spec.lua'` in a real terminal (or agent-terminal). It checks screen attributes through the right edge for centered/left-aligned, focused, empty-row, and split-window output. `MERMAID_TEST_RESULT` optionally writes a JSON verdict for automation.

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

Only `require('render-markdown-mermaid').setup(opts)` is a public Lua interface. The `M.config` field is set after setup. Commands: `:MermaidFocus`, `:MermaidCycle[!]`. Plug mappings: `(MermaidCycle)` / `(MermaidCycleBack)`. The viewer maps q/Esc to exit and Tab/Shift-Tab to cycle engines; source movement/Tab keys are untouched. `focus_key` (Enter by default) is context-sensitive in Markdown/MDX.

## `autoload/health/` is empty

Health check is implemented in `lua/render-markdown-mermaid/health.lua` via the Lua health API, not the legacy Vimscript `autoload/health/` pattern. The empty directory can be ignored.
