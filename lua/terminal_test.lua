local M = {}
local make_notify = require('mini.notify').make_notify {}
local ns = vim.api.nvim_create_namespace 'GoTestError'
local terminal_multiplexer = require 'terminal_multiplexer'
M.terminals_tests = terminal_multiplexer.new()

M.toggle_view_enclosing_test = function()
  local test_name = Get_enclosing_test()
  assert(test_name, 'No test found')
  local float_terminal_state = M.terminals_tests:toggle_float_terminal(test_name)
  assert(float_terminal_state, 'Failed to create floating terminal')

  -- Need this duplication. Otherwise, the keymap is bind to the buffer for for some reason
  local close_term = function()
    if vim.api.nvim_win_is_valid(float_terminal_state.footer_win) then
      vim.api.nvim_win_hide(float_terminal_state.footer_win)
    end
    if vim.api.nvim_win_is_valid(float_terminal_state.win) then
      vim.api.nvim_win_hide(float_terminal_state.win)
    end
  end
  vim.keymap.set('n', 'q', close_term, { buffer = float_terminal_state.buf })
end

M.go_test_command = function(test_info)
  assert(test_info.test_name, 'No test found')
  assert(test_info.test_bufnr, 'No test buffer found')
  assert(test_info.test_line, 'No test line found')
  assert(test_info.test_command, 'No test command found')
  assert(vim.api.nvim_buf_is_valid(test_info.test_bufnr), 'Invalid buffer')
  local test_name = test_info.test_name
  local test_line = test_info.test_line
  local test_command = test_info.test_command
  local source_bufnr = test_info.test_bufnr
  M.terminals_tests:toggle_float_terminal(test_name)
  local float_term_state = M.terminals_tests:toggle_float_terminal(test_name)
  assert(float_term_state, 'Failed to create floating terminal')
  vim.api.nvim_chan_send(float_term_state.chan, test_command .. '\n')

  local notification_sent = false
  vim.api.nvim_buf_attach(float_term_state.buf, false, {
    on_lines = function(_, buf, _, first_line, last_line)
      local lines = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)
      local current_time = os.date '%H:%M:%S'
      local error_line

      for _, line in ipairs(lines) do
        if string.match(line, '--- FAIL') then
          vim.api.nvim_buf_set_extmark(source_bufnr, ns, test_line - 1, 0, {
            virt_text = { { string.format('❌ %s', current_time) } },
            virt_text_pos = 'eol',
          })
          test_info.status = 'failed'
          float_term_state.status = 'failed'

          make_notify(string.format('Test failed: %s', test_name))
          vim.notify(string.format('Test failed: %s', test_name), vim.log.levels.WARN, { title = 'Test Failure' })
          notification_sent = true
          return true
        elseif string.match(line, '--- PASS') then
          vim.api.nvim_buf_set_extmark(source_bufnr, ns, test_line - 1, 0, {
            virt_text = { { string.format('✅ %s', current_time) } },
            virt_text_pos = 'eol',
          })
          test_info.status = 'passed'
          float_term_state.status = 'passed'

          if not notification_sent then
            make_notify(string.format('Test passed: %s', test_name))
            notification_sent = true
            return true -- detach from the buffer
          end
        end

        -- Pattern matches strings like "Error Trace:    /Users/path/file.go:21"
        local file, line_num = string.match(line, 'Error Trace:%s+([^:]+):(%d+)')

        if file and line_num then
          error_line = tonumber(line_num)

          -- Try to find the buffer for this file
          local error_bufnr
          for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
            local buf_name = vim.api.nvim_buf_get_name(buf_id)
            if buf_name:match(file .. '$') then
              error_bufnr = buf_id
              break
            end
          end

          if error_bufnr then
            vim.fn.sign_define('GoTestError', { text = '✗', texthl = 'DiagnosticError' })
            vim.fn.sign_place(0, 'GoTestErrorGroup', 'GoTestError', error_bufnr, { lnum = error_line })
          end
        end
      end

      -- Only detach if we're done processing (when test is complete)
      if notification_sent and error_line then
        return true
      end

      return false
    end,
  })
end

local function test_buf(test_format)
  local source_bufnr = vim.api.nvim_get_current_buf()
  local testsInCurrBuf = Find_all_tests(source_bufnr)
  for test_name, test_line in pairs(testsInCurrBuf) do
    M.terminals_tests:delete_terminal(test_name)
    local test_command = string.format(test_format, test_name)
    local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
    make_notify(string.format('Running test: %s', test_name))
    M.go_test_command(test_info)
  end
end

local function Get_enclosing_fn_info()
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
      return startLine + 1, func_name -- +1 to convert 0-based to 1-based lua indexing system
    end
    ::continue::
  end

  return nil
end

local function get_enclosing_test()
  local test_line, testName = Get_enclosing_fn_info()
  if not testName then
    print 'Not in a function'
    return nil
  end
  if not string.match(testName, 'Test_') then
    print(string.format('Not in a test function: %s', testName))
    return nil
  end
  return testName, test_line
end

M.get_test_info_enclosing_test = function()
  local test_name, test_line = get_enclosing_test()
  if not test_name then
    make_notify 'No test found'
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

---@return  testInfo | nil
M.go_integration_test = function()
  local test_info = M.get_test_info_enclosing_test()
  if not test_info then
    return nil
  end
  M.terminals_tests:delete_terminal(test_info.test_name)
  M.go_test_command(test_info)
  make_notify(string.format('Running test: %s', test_info.test_name))
  return test_info
end

M.drive_test_dev = function()
  vim.env.MODE, vim.env.UKS = 'dev', 'others'
  M.go_integration_test()
end

M.drive_test_staging = function()
  vim.env.MODE, vim.env.UKS = 'staging', 'others'
  M.go_integration_test()
end

M.windows_test_buf = function()
  local test_format = 'gitBash -c "go test integration_tests/*.go -v -run %s"\r'
  test_buf(test_format)
end

M.drive_test_dev_buf = function()
  vim.env.MODE, vim.env.UKS = 'dev', 'others'
  local test_format = 'go test integration_tests/*.go -v -run %s'
  test_buf(test_format)
end

M.drive_test_staging_buf = function()
  vim.env.MODE, vim.env.UKS = 'staging', 'others'
  local test_format = 'go test integration_tests/*.go -v -run %s'
  test_buf(test_format)
end

M.go_normal_test = function()
  local source_bufnr = vim.api.nvim_get_current_buf()
  local test_name, test_line = get_enclosing_test()
  M.terminals_tests:delete_terminal(test_name)
  assert(test_name, 'No test found')
  local test_command = string.format('go test ./... -v -run %s\r\n', test_name)
  local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
  M.go_test_command(test_info)
end

M.test_normal_buf = function()
  local test_format = 'go test ./... -v -run %s'
  test_buf(test_format)
end

M.toggle_last_test = function()
  local test_name = M.terminals_tests.last_terminal_name
  if not test_name then
    make_notify 'No last test found'
    return
  end
  M.terminals_tests:toggle_float_terminal(test_name)
end

return M
