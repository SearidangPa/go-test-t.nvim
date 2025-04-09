local M = {}

M.get_test_info_enclosing_test = function()
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  if not test_name then
    vim.notify('Not in a test function', vim.log.levels.WARN)
    return nil
  end

  local test_command
  if vim.fn.has 'win32' == 1 then
    test_command = string.format('gitBash -c "go test integration_tests/*.go -v -race -run %s"\r', test_name)
  else
    test_command = string.format('go test integration_tests/*.go -v -run %s', test_name)
  end
  local source_bufnr = vim.api.nvim_get_current_buf()
  local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
  return test_info
end

---@return  string | nil, number | nil
M.get_enclosing_test = function()
  local ts_utils = require 'nvim-treesitter.ts_utils'
  local node = ts_utils.get_node_at_cursor()
  while node do
    if node:type() ~= 'function_declaration' then
      node = node:parent() -- Traverse up the node tree to find a function node
      goto continue
    end

    local func_name_node = node:child(1)
    if func_name_node then
      local func_name = vim.treesitter.get_node_text(func_name_node, 0)
      local startLine, _, _ = node:start()
      if not string.match(func_name, 'Test_') then
        print(string.format('Not in a test function: %s', func_name))
        return nil
      end
      return func_name, startLine + 1 -- +1 to convert 0-based to 1-based lua indexing system
    end
    ::continue::
  end

  return nil, nil
end


-- maybe this is not needed
local function_query = [[
(function_declaration
  name: (identifier) @name
  parameters: (parameter_list
    (parameter_declaration
      name: (identifier)
      type: (pointer_type
        (qualified_type
          package: (package_identifier) @_package_name
          name: (type_identifier) ))))
)
]]

M.find_all_tests = function (go_bufnr)
  local query = vim.treesitter.query.parse('go', function_query)
  local parser = vim.treesitter.get_parser(go_bufnr, 'go', {})
  assert(parser, 'parser is nil')
  local tree = parser:parse()[1]
  local root = tree:root()
  assert(root, 'root is nil')

  local res = {}
  for _, node in query:iter_captures(root, go_bufnr, 0, -1) do
    if node == nil then
      return res
    end
    local nodeContent = vim.treesitter.get_node_text(node, go_bufnr)

    -- all tests start with Test
    if not string.match(nodeContent, 'Test') then
      goto continue
    end

    res[nodeContent] = node:start() + 1
    ::continue::
  end
  return res
end

return M
