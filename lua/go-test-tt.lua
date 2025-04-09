local M = {}

M.test_track_list = function()
  local terminal_test = require 'terminals.terminal_test'
  local tracker = require 'terminals.terminal_tracker'

  local make_notify = require('mini.notify').make_notify {}
  for _, test_info in ipairs(tracker.test_tracker) do
    make_notify(string.format('Running test: %s', test_info.test_name)).go_test_command(test_info)
    terminal_test.go_terminal_test_command(test_info)
  end
end

M.setup = function()
  local terminal_test = require 'terminals.terminal_test'
  vim.api.nvim_create_user_command('TerminalTestSearch', function() terminal_test.terminals:search_terminal() end, {})
  vim.api.nvim_create_user_command('TerminalTestDelete', function() terminal_test.terminals:select_delete_terminal() end, {})
  vim.api.nvim_create_user_command('TerminalTestToggleView', terminal_test.toggle_view_enclosing_test, {})
  vim.api.nvim_create_user_command('TerminalTestToggleLast', terminal_test.toggle_last_test, {})

  vim.api.nvim_create_user_command('GoTestNormalBuf', terminal_test.test_normal_buf, {})
  vim.api.nvim_create_user_command('GoTestNormal', terminal_test.go_normal_test, {})

  vim.api.nvim_create_user_command('GoTestDriveDev', terminal_test.drive_test_dev, {})
  vim.api.nvim_create_user_command('GoTestDriveStaging', terminal_test.drive_test_staging, {})
  vim.api.nvim_create_user_command('GoTestDriveStagingBuf', terminal_test.drive_test_staging_buf, {})
  vim.api.nvim_create_user_command('GoTestDriveDevBuf', terminal_test.drive_test_dev_buf, {})
  vim.api.nvim_create_user_command('GoTestWindowsBuf', terminal_test.windows_test_buf, {})
  vim.api.nvim_create_user_command('GoTestIntegration', terminal_test.go_integration_test, {})

  require 'test_all'
  require 'terminals.terminal_tracker'
end

return M
