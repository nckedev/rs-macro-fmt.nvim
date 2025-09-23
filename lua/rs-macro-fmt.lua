---@enum bracket
local BRACKET = {
  open = '{',
  close = '}'
}

local function count_leading_ws(line)
  local count = 0
  for i = 1, #line do
    local c = line:sub(i, i)
    if c == " " then
      count = count + 1
    else
      break
    end
  end
  return count
end

-- Calculates what level of indent the current line should have
-- returns current, next
--- @param line string the line to calculate without leading whitespace
--- @return integer,  integer
local function calculate_indent_level(line)
  -- TODO: dont count brackets inside a string
  local balance = 0
  local in_str = false
  local first = string.sub(line, 1, 1) or ''
  local last = string.sub(line, #line, #line) or ''

  assert(first ~= " ", "string cant have any leading whitespace")

  for i = 1, #line do
    local c = string.sub(line, i, i)
    if c == BRACKET.open and not in_str then
      balance = balance + 1
    elseif c == BRACKET.close and not in_str then
      balance = balance - 1
    elseif c == "\"" then
      in_str = not in_str
    end
  end

  -- } {
  if balance == 0 and first == BRACKET.close and last == BRACKET.open then
    return -1, 1
    -- {}
  elseif balance == 0 then -- and first == BRACKET.open and last == BRACKET.close then
    return 0, 0
    -- {
  elseif balance > 0 then
    return 0, 1
    -- }
  elseif balance < 0 then
    return -1, 0
  else
    return 0, 0
  end
end

local function fmt(bufnr, opts)
  if vim.bo.filetype ~= "rust" then
    vim.notify("only rust files are supported", vim.log.levels.ERROR)
    return
  end
  local language_tree = vim.treesitter.get_parser(bufnr, "rust")
  if language_tree == nil then
    vim.notify("No treesitter parser for rust found", vim.log.levels.ERROR)
    return
  end
  local syntax_tree = language_tree:parse()
  if syntax_tree == nil then
    vim.notify("no tree", vim.log.levels.ERROR)
    return
  end
  local root = syntax_tree[1]:root()
  local query = vim.treesitter.query.parse("rust", [[
 (macro_invocation
   macro: (identifier) @ident (#eq? @ident "html")(#offset! @ident)
   (token_tree) @tree)
]])

  for id, node, metadata, match in query:iter_captures(root, bufnr) do
    local name = query.captures[id]
    if (name == "tree") then
      -- { start_row, start_col, end_row, end_col }
      local range = { node:range(false) }
      local row = range[1]
      local lines = vim.api.nvim_buf_get_lines(bufnr, row, range[3] + 1, false)
      local offset = count_leading_ws(lines[1])
      local current_indent = offset

      for _, line in ipairs(lines) do
        local no_indent_line = string.sub(line, count_leading_ws(line) + 1)

        -- if the line have more closing than opening brackets -> decrese the indent level
        local current, next = calculate_indent_level(no_indent_line)
        current_indent = current_indent + (current * opts.indent_size)

        -- write the line to the buffer
        vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false,
          { string.rep(" ", current_indent) .. no_indent_line })

        -- set the indent level for the next line
        current_indent = current_indent + (next * opts.indent_size)

        row = row + 1
      end
    end
  end
end

--- @type Options
local defaults = {
  enabled = false,
  macro_identifier = "html",
  indent_size = 4,
  autoformat_on_save = true,
  format_class_string = true,
}

local M = {}

---@param opts Options
function M.setup(opts)
  -- overwrite the defaults with opts if they are set
  --- @type Options
  opts = vim.tbl_extend("force", defaults, opts or {})

  if not opts.enabled then return end

  vim.api.nvim_create_user_command("RsMacroFmt", function() fmt(0, opts) end, {})

  if opts.autoformat_on_save == true then
    vim.api.nvim_create_autocmd({ 'BufWritePre' }, {
      pattern = { '*.rs' },
      callback = function(ev)
        -- print(string.format('event fired: %s', vim.inspect(ev)))
        fmt(0, opts)
      end
    })
  end
end

M._private = { count_leading_ws = count_leading_ws }

return M
