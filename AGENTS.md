# AGENTS.md

## What this repo is

A Neovim plugin (`render-markdown-mermaid.nvim`) that renders fenced `mermaid` code blocks inline using `render-markdown.nvim` and either `bm` (Beautiful Mermaid) or `mermaid-ascii` as the CLI backend.

## Key architecture

- **Entrypoint**: `lua/render-markdown-mermaid/init.lua` — `M.setup(opts)` is the only public API. Users call it via lazy.nvim `opts = {}`. The plugin guard in `plugin/render-markdown-mermaid.lua` does NOT call setup.
- **Rendering pipeline**: `display.lua` (treesitter query → cache check → async `vim.system()` call) → `renderer.lua` (builds CLI args for `bm` or `mermaid-ascii`) → result placed as extmark virtual lines.
- **Cache**: `cache.lua` keys on `sha256(json({source, cmd, mode, cli}))`.
- **Config resolution**: `config.lua` — `cmd` auto-resolves to first available of `['bm', 'mermaid-ascii']`; `mode` defaults to `'unicode'`; `placement` defaults to `'above'`.

## No tooling currently present

There is **no CI, no Makefile, no test suite, no linter config, no formatter config**. Manual testing is done by opening a Markdown file in Neovim with the plugin loaded.

## Smoke test

Open `samples/one-pager.md` or `samples/sequence_diagrams.md` in Neovim. Run `:checkhealth render-markdown-mermaid` to verify dependencies.

## Requirements to verify behavior

- Neovim 0.10+
- `bm` (`beautiful-mermaid`) or `mermaid-ascii` in `PATH`
- `nvim-treesitter` with `markdown` and `markdown_inline` parsers installed (`:TSInstall markdown markdown_inline`)
- `render-markdown.nvim` installed

## Treesitter query

`display.lua` parses `markdown` using an inline treesitter query — the `queries/markdown/` directory is intentionally empty (no bundled queries files). The query is defined as a string literal in `display.lua`.

## Public API surface

Only `require('render-markdown-mermaid').setup(opts)` is public. The `M.config` field is set after setup. No commands or keymaps are registered by the plugin.

## `autoload/health/` is empty

Health check is implemented in `lua/render-markdown-mermaid/health.lua` via the Lua health API, not the legacy Vimscript `autoload/health/` pattern. The empty directory can be ignored.
