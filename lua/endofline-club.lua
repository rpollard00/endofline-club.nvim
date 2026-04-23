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
  --- Keep showing the last resolved text while Neovim is rendering an unresolved
  --- codelens placeholder. This avoids a brief disappear/reappear flicker for
  --- servers that resolve lenses asynchronously.
  preserve_unresolved_lenses = true,
  --- Maximum number of remembered resolved lens lines per buffer.
  max_preserved_lenses = 512,
  --- Namespace name prefixes that should be converted. Defaults cover Neovim's LSP codelens.
  namespace_prefixes = { 'nvim.lsp.codelens' },
}

local state = {
  installed = false,
  enabled = true,
  opts = vim.deepcopy(defaults),
  original_set_extmark = nil,
  namespace_cache = {},
  lens_cache = {},
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

local function cache_key(bufnr, ns, line)
  if not state.opts.preserve_unresolved_lenses then
    return nil
  end

  local ok, lines = pcall(api.nvim_buf_get_lines, bufnr, line, line + 1, false)
  if not ok or not lines or not lines[1] then
    return nil
  end

  return tostring(ns) .. '\0' .. lines[1]
end

local function remember_chunks(bufnr, key, chunks)
  if not key or #chunks == 0 then
    return
  end

  local cache = state.lens_cache[bufnr]
  if not cache then
    cache = { entries = {}, order = {} }
    state.lens_cache[bufnr] = cache
  end

  if not cache.entries[key] then
    table.insert(cache.order, key)
  end
  cache.entries[key] = vim.deepcopy(chunks)

  local max = state.opts.max_preserved_lenses or defaults.max_preserved_lenses
  while max > 0 and #cache.order > max do
    local old_key = table.remove(cache.order, 1)
    cache.entries[old_key] = nil
  end
end

local function recall_chunks(bufnr, key)
  local cache = state.lens_cache[bufnr]
  local chunks = cache and cache.entries[key]
  return chunks and vim.deepcopy(chunks) or nil
end

local function convert_chunks(chunks, bufnr, ns, line)
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

  -- Native codelens may briefly render an empty placeholder while resolving.
  -- Reuse the last resolved text for this line when possible; otherwise do not
  -- create an extmark with only our prefix.
  local key = cache_key(bufnr, ns, line)

  if not has_visible_text then
    return recall_chunks(bufnr, key) or {}
  end

  if state.opts.prefix and state.opts.prefix ~= '' then
    table.insert(out, { state.opts.prefix, state.opts.prefix_hl })
  end
  vim.list_extend(out, body)
  remember_chunks(bufnr, key, out)

  return out
end

local function convert_opts(opts, bufnr, ns, line)
  local chunks = first_virtual_line(opts.virt_lines)
  if not chunks then
    return opts
  end

  local new_opts = vim.deepcopy(opts)
  new_opts.virt_lines = nil
  new_opts.virt_lines_above = nil
  new_opts.virt_lines_leftcol = nil
  new_opts.virt_lines_overflow = nil
  new_opts.virt_text = convert_chunks(chunks, bufnr, ns, line)
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
      opts = convert_opts(opts, bufnr, ns, line)
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
  state.lens_cache = {}
end

--- Setup endofline-club.nvim.
---@param opts? table
function M.setup(opts)
  state.opts = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  state.enabled = state.opts.enabled ~= false
  state.namespace_cache = {}
  state.lens_cache = {}
  install()
end

function M._state()
  return state
end

return M
