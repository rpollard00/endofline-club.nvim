# endofline-club.nvim

A tiny Neovim plugin that renders LSP codelens with `virtual_text` at the end of the line instead of Neovim's native `virtual_lines` rendering.

Neovim 0.10+ moved codelens into virtual lines. That can cause visual disruption and layout shifting, especially for LSPs that produce many lenses. `endofline-club.nvim` keeps codelens on the same buffer line and stays LSP-agnostic.

## Features

- Uses end-of-line `virtual_text` for codelens.
- Avoids layout shifting from `virtual_lines`.
- LSP-agnostic: works with Neovim's built-in codelens renderer rather than special-casing servers.
- Fast and small: only intercepts codelens extmarks.
- No codelens command/run behavior changes.

## Requirements

- Neovim 0.10+

## Installation

### lazy.nvim

```lua
{
  'reese/endofline-club.nvim',
  opts = {},
}
```

### packer.nvim

```lua
use {
  'reese/endofline-club.nvim',
  config = function()
    require('endofline-club').setup()
  end,
}
```

The plugin also auto-enables from `plugin/endofline-club.lua`, so it works with a normal package-manager load even without an explicit `setup()` call. Calling `setup()` yourself is safe and lets you override options.

## Configuration

Defaults:

```lua
require('endofline-club').setup({
  enabled = true,

  -- `eol` avoids layout shifts. You may also use `right_align` or `inline`.
  virt_text_pos = 'eol',

  -- Text displayed before codelens chunks.
  prefix = '  ',
  prefix_hl = 'LspCodeLensSeparator',

  -- Native codelens virtual-lines include indentation padding. That padding is
  -- useful above the line, but ugly at EOL, so it is stripped by default.
  strip_virtual_line_padding = true,

  -- Namespace prefixes to convert. The default matches Neovim's codelens namespaces.
  namespace_prefixes = { 'nvim.lsp.codelens' },
})
```

## Commands / API

```lua
require('endofline-club').enable()
require('endofline-club').disable()
print(require('endofline-club').is_enabled())
```

Disabling affects future codelens renders. If you want to immediately redraw current lenses after toggling, run:

```lua
vim.lsp.codelens.refresh({ bufnr = 0 })
```

## How it works

Neovim's LSP codelens code already handles requesting, resolving, sorting, refreshing, clearing, and running lenses. This plugin leaves all of that intact.

Instead, it wraps `vim.api.nvim_buf_set_extmark` and only converts extmarks in Neovim's codelens namespaces (`nvim.lsp.codelens...`) that contain `virt_lines`. Those extmark options are rewritten to use `virt_text` with `virt_text_pos = 'eol'`.

That keeps the plugin independent of particular LSP servers and avoids duplicating Neovim's codelens implementation.

## License

MIT
