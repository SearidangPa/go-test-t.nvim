local util_lsp = {}

---@class lsp_param
---@field test_line integer
---@field test_bufnr integer
---@field filepath string
---@class util_lsp
---@field action_from_test_name fun(test_name: string, cb: fun(cb_param: lsp_param))

---@param callback_func fun(lsp_param: lsp_param)
function util_lsp.action_from_test_name(test_name, callback_func)
  local go_clients = vim.lsp.get_clients { name = 'gopls' }
  if #go_clients == 0 then
    vim.notify('No Go language server found', vim.log.levels.ERROR)
    return
  end
  local client = go_clients[1]
  local params = { query = test_name }

  local handler = function(err, res, _)
    if err or not res or #res == 0 then
      vim.notify('No definition found for test: ' .. test_name, vim.log.levels.WARN)
      return
    end
    local result = res[1]
    local filename = vim.uri_to_fname(result.location.uri)
    local start = result.location.range.start
    local file_bufnr = vim.fn.bufadd(filename)
    vim.fn.bufload(file_bufnr)
    callback_func {
      test_line = start.line + 1,
      test_bufnr = file_bufnr,
      filepath = filename,
    }
  end

  client:request('workspace/symbol', params, handler)
end

return util_lsp
