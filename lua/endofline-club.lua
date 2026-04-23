local M = {}

local api = vim.api

local defaults = {
  enabled = true,
  --- Where to place the codelens text. Use "eol" to avoid layout shifts.
  --- Other useful values are "right_align" and "inline". See :help nvim_buf_set_extmark().
  virt_text_pos = 'eol',
  --- Text inserted before the first codelens chunk.
  prefix = '  ',
  --- Highlight group for prefix text.
  prefix_hl = 'LspCodeLensSeparator',
  --- Strip Neovim's virtual-line indentation padding before rendering at EOL.
  strip_virtual_line_padding = true,
  --- Namespace name prefixes that should be converted. Defaults cover Neovim's LSP codelens.
  namespace_prefixes = { 'nvim.lsp.codelens' },
}

local state = {
  installed = false,
  enabled = true,
  opts = vim.deepcopy(defaults),
  original_set_extmark = nil,
  namespace_cache = {},
}

local function starts_with(s, prefix)
  return s:sub(1, #prefix) == prefix
end

local function is_codelens_namespace(ns)
  local cached = state.namespace_cache[ns]
  if cached ~= nil then
    return cached
  end

  local ok, namespaces = pcall(api.nvim_get_namespaces)
  if not ok then
    state.namespace_cache[ns] = false
    return false
  end

  local name
  for n, id in pairs(namespaces) do
    if id == ns then
      name = n
      break
    end
  end

  local matched = false
  if name then
    for _, prefix in ipairs(state.opts.namespace_prefixes) do
      if starts_with(name, prefix) then
        matched = true
        break
      end
    end
  end

  state.namespace_cache[ns] = matched
  return matched
end

local function first_virtual_line(virt_lines)
  if type(virt_lines) ~= 'table' then
    return nil
  end

  -- Neovim codelens uses: virt_lines = { virt_text_chunks }
  local line = virt_lines[1]
  if type(line) ~= 'table' then
    return nil
  end

  return line
end

local function is_padding_chunk(chunk)
  return type(chunk) == 'table'
    and type(chunk[1]) == 'string'
    and chunk[1]:match('^%s*$') ~= nil
end

local function convert_chunks(chunks)
  local out = {}
  local start = 1

  if state.opts.strip_virtual_line_padding then
    while chunks[start] and is_padding_chunk(chunks[start]) do
      start = start + 1
    end
  end

  local body = {}
  local has_visible_text = false
  for i = start, #chunks do
    local chunk = chunks[i]
    -- Copy the chunk table so later mutations by Neovim/LSP code cannot surprise us.
    if type(chunk) == 'table' then
      if type(chunk[1]) == 'string' and chunk[1]:match('%S') then
        has_visible_text = true
      end
      table.insert(body, vim.deepcopy(chunk))
    end
  end

  -- Native codelens may briefly render an empty placeholder while resolving. Do not
  -- create an extmark with only our prefix for that case.
  if not has_visible_text then
    return {}
  end

  if state.opts.prefix and state.opts.prefix ~= '' then
    table.insert(out, { state.opts.prefix, state.opts.prefix_hl })
  end
  vim.list_extend(out, body)

  return out
end

local function convert_opts(opts)
  local chunks = first_virtual_line(opts.virt_lines)
  if not chunks then
    return opts
  end

  local new_opts = vim.deepcopy(opts)
  new_opts.virt_lines = nil
  new_opts.virt_lines_above = nil
  new_opts.virt_lines_leftcol = nil
  new_opts.virt_lines_overflow = nil
  new_opts.virt_text = convert_chunks(chunks)
  new_opts.virt_text_pos = state.opts.virt_text_pos

  -- Keep codelens visually subtle and composable with user highlights.
  new_opts.hl_mode = new_opts.hl_mode or 'combine'

  return new_opts
end

local function install()
  if state.installed then
    return
  end

  state.original_set_extmark = api.nvim_buf_set_extmark

  api.nvim_buf_set_extmark = function(bufnr, ns, line, col, opts)
    if state.enabled
      and type(opts) == 'table'
      and opts.virt_lines ~= nil
      and is_codelens_namespace(ns)
    then
      opts = convert_opts(opts)
    end

    return state.original_set_extmark(bufnr, ns, line, col, opts)
  end

  state.installed = true
end

--- Enable EOL codelens conversion.
function M.enable()
  state.enabled = true
end

--- Disable EOL conversion. Future codelens renders use Neovim's native behavior.
function M.disable()
  state.enabled = false
end

function M.is_enabled()
  return state.enabled
end

--- Clear namespace cache. Mostly useful for tests or unusual runtime namespace creation.
function M.reset_cache()
  state.namespace_cache = {}
end

--- Setup endofline-club.nvim.
---@param opts? table
function M.setup(opts)
  state.opts = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  state.enabled = state.opts.enabled ~= false
  state.namespace_cache = {}
  install()
end

function M._state()
  return state
end

return M
