local terminal_test = {}
local make_notify = require('mini.notify').make_notify {}
local ns = vim.api.nvim_create_namespace 'GoTestError'
local terminal_multiplexer = require 'terminals.terminal_multiplexer'
terminal_test.terminals = terminal_multiplexer.new()

terminal_test.toggle_view_enclosing_test = function()
  local util_find_test = require 'util_find_test'
  local test_name, _ = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  local float_terminal_state = terminal_test.terminals:toggle_float_terminal(test_name)
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

terminal_test.go_terminal_test_command = function(test_info)
  assert(test_info.test_name, 'No test found')
  assert(test_info.test_bufnr, 'No test buffer found')
  assert(test_info.test_line, 'No test line found')
  assert(test_info.test_command, 'No test command found')
  assert(vim.api.nvim_buf_is_valid(test_info.test_bufnr), 'Invalid buffer')
  local test_name = test_info.test_name
  local test_line = test_info.test_line
  local test_command = test_info.test_command
  local source_bufnr = test_info.test_bufnr
  terminal_test.terminals:toggle_float_terminal(test_name)
  local float_term_state = terminal_test.terminals:toggle_float_terminal(test_name)
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

terminal_test.test_buf = function(test_format)
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'util_find_test'
  local testsInCurrBuf = util_find_test.find_all_tests(source_bufnr)
  for test_name, test_line in pairs(testsInCurrBuf) do
    terminal_test.terminals:delete_terminal(test_name)
    local test_command = string.format(test_format, test_name)
    local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
    make_notify(string.format('Running test: %s', test_name))
    terminal_test.go_terminal_test_command(test_info)
  end
end

terminal_test.get_test_info_enclosing_test = function()
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
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

terminal_test.go_integration_test = function()
  local test_info = terminal_test.get_test_info_enclosing_test()
  if not test_info then
    return nil
  end
  terminal_test.terminals:delete_terminal(test_info.test_name)
  terminal_test.go_terminal_test_command(test_info)
  make_notify(string.format('Running test: %s', test_info.test_name))
end

terminal_test.drive_test_dev = function()
  vim.env.MODE, vim.env.UKS = 'dev', 'others'
  terminal_test.go_integration_test()
end

terminal_test.drive_test_staging = function()
  vim.env.MODE, vim.env.UKS = 'staging', 'others'
  terminal_test.go_integration_test()
end

terminal_test.windows_test_buf = function()
  local test_format = 'gitBash -c "go test integration_tests/*.go -v -run %s"\r'
  terminal_test.test_buf(test_format)
end

terminal_test.drive_test_dev_buf = function()
  vim.env.MODE, vim.env.UKS = 'dev', 'others'
  local test_format = 'go test integration_tests/*.go -v -run %s'
  terminal_test.test_buf(test_format)
end

terminal_test.drive_test_staging_buf = function()
  vim.env.MODE, vim.env.UKS = 'staging', 'others'
  local test_format = 'go test integration_tests/*.go -v -run %s'
  terminal_test.test_buf(test_format)
end

terminal_test.go_normal_test = function()
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  assert(test_line, 'No test line found')
  terminal_test.terminals:delete_terminal(test_name)
  assert(test_name, 'No test found')
  local test_command = string.format('go test ./... -v -run %s\r\n', test_name)
  local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
  terminal_test.go_terminal_test_command(test_info)
end

terminal_test.test_normal_buf = function()
  local test_format = 'go test ./... -v -run %s'
  terminal_test.test_buf(test_format)
end

terminal_test.toggle_last_test = function()
  local test_name = terminal_test.terminals.last_terminal_name
  if not test_name then
    make_notify 'No last test found'
    return
  end
  terminal_test.terminals:toggle_float_terminal(test_name)
end

return terminal_test
