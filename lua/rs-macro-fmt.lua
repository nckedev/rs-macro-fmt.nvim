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

-- checks the balance of brackets for given line
-- returns a positive integer (the difference) if there are more opening brackets than closing
-- returns a negative integer (the difference) if there are more closing than opening
-- returns 0 if they are balanced
local function line_bracket_balance(line)
  -- TODO: dont count brackets inside a string
  local balance = 0
  local in_str = false
  for i = 1, #line do
    local c = string.sub(line, i, i)
    if c == "{" and not in_str then
      balance = balance + 1
    elseif c == "}" and not in_str then
      balance = balance - 1
    elseif c == "\"" then
      in_str = not in_str
    end
  end
  return balance
end

local function ends_with_open_bracket(line)
  return string.sub(line, -1) == '{'
end

local function is_close_bracket(line)
  return string.sub(line, 1, 1) == '}' or string.sub(line, 1, 2) == "};"
end

local function fmt(bufnr, opts)
  if vim.bo.filetype ~= "rust" then
    vim.notify("only rust files are supported", vim.log.levels.WARN)
    return
  end
  local language_tree = vim.treesitter.get_parser(bufnr, "rust")
  if language_tree == nil then
    vim.notify("No treesitter parser for rust found")
    return
  end
  local syntax_tree = language_tree:parse()
  if syntax_tree == nil then
    print("no tree")
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
        -- TODO: balance the line and move each new closing to a new line
        if (line_bracket_balance(no_indent_line) < 0) then
          current_indent = current_indent - opts.indent_size
        end

        -- write the line to the buffer
        vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false,
          { string.rep(" ", current_indent) .. no_indent_line })

        -- if the line has more opening than closing brackets -> increase the indent level
        if (line_bracket_balance(line) > 0) then
          current_indent = current_indent + opts.indent_size
        end
        row = row + 1
      end
    end
  end
end

local defaults = {
  enabled = true,
  macro_identifier = "html",
  indent_size = 4,
  autoformat_on_save = true,
  format_class_string = true,
}

local M = {}

function M.setup(opts)
  -- overwrite the defaults with opts if they are set
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

return M
