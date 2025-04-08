local M = {}
require 'config.util_find_func'
local make_notify = require('mini.notify').make_notify {}
local map = vim.keymap.set
local ns = vim.api.nvim_create_namespace 'GoTestError'
local terminal_multiplexer = require 'config.terminal_multiplexer'
M.terminals_tests = terminal_multiplexer.new()

local function toggle_view_enclosing_test()
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
    for index, existing_test_info in ipairs(M.test_tracker) do
      if existing_test_info.test_name == test_info.test_name then
        M.test_tracker[index] = test_info
      end
    end
    M.go_test_command(test_info)
  end
end

M.get_test_info_enclosing_test = function()
  local test_name, test_line = Get_enclosing_test()
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
local function go_integration_test()
  local test_info = M.get_test_info_enclosing_test()
  if not test_info then
    return nil
  end
  M.terminals_tests:delete_terminal(test_info.test_name)
  M.go_test_command(test_info)
  make_notify(string.format('Running test: %s', test_info.test_name))
  return test_info
end

local function drive_test_dev()
  vim.env.MODE, vim.env.UKS = 'dev', 'others'
  go_integration_test()
end

local function drive_test_staging()
  vim.env.MODE, vim.env.UKS = 'staging', 'others'
  go_integration_test()
end

local function windows_test_buf()
  local test_format = 'gitBash -c "go test integration_tests/*.go -v -run %s"\r'
  test_buf(test_format)
end

local function drive_test_dev_buf()
  vim.env.MODE, vim.env.UKS = 'dev', 'others'
  local test_format = 'go test integration_tests/*.go -v -run %s'
  test_buf(test_format)
end

local function drive_test_staging_buf()
  vim.env.MODE, vim.env.UKS = 'staging', 'others'
  local test_format = 'go test integration_tests/*.go -v -run %s'
  test_buf(test_format)
end

local go_normal_test = function()
  local source_bufnr = vim.api.nvim_get_current_buf()
  local test_name, test_line = Get_enclosing_test()
  M.terminals_tests:delete_terminal(test_name)
  assert(test_name, 'No test found')
  local test_command = string.format('go test ./... -v -run %s\r\n', test_name)
  local test_info = { test_name = test_name, test_line = test_line, test_bufnr = source_bufnr, test_command = test_command }
  M.go_test_command(test_info)
end

local function test_normal_buf()
  local test_format = 'go test ./... -v -run %s'
  test_buf(test_format)
end

local function toggle_last_test()
  local test_name = M.terminals_tests.last_terminal_name
  if not test_name then
    make_notify 'No last test found'
    return
  end
  M.terminals_tests:toggle_float_terminal(test_name)
end

vim.api.nvim_create_user_command('GoTestSearch', function() M.terminals_tests:search_terminal() end, {})
vim.api.nvim_create_user_command('GoTestDelete', function() M.terminals_tests:select_delete_terminal() end, {})
vim.api.nvim_create_user_command('GoTestNormalBuf', test_normal_buf, {})
vim.api.nvim_create_user_command('GoTestNormal', go_normal_test, {})
vim.api.nvim_create_user_command('GoTestDriveDev', drive_test_dev, {})
vim.api.nvim_create_user_command('GoTestDriveStaging', drive_test_staging, {})
vim.api.nvim_create_user_command('GoTestDriveStagingBuf', drive_test_staging_buf, {})
vim.api.nvim_create_user_command('GoTestDriveDevBuf', drive_test_dev_buf, {})
vim.api.nvim_create_user_command('GoTestWindowsBuf', windows_test_buf, {})
vim.api.nvim_create_user_command('GoTestIntegration', go_integration_test, {})

vim.keymap.set('n', '<leader>G', go_integration_test, { desc = 'Go integration test' })
vim.keymap.set('n', '<leader>st', function() M.terminals_tests:search_terminal() end, { desc = 'Select test terminal' })
vim.keymap.set('n', '<leader>tf', function() M.terminals_tests:search_terminal(true) end, { desc = 'Select test terminal with pass filter' })
vim.keymap.set('n', '<leader>tg', toggle_view_enclosing_test, { desc = 'Toggle go test terminal' })
vim.keymap.set('n', '<leader>tl', toggle_last_test, { desc = 'Toggle last go test terminal' })

return M
