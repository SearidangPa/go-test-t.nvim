local M = {}

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

return M
