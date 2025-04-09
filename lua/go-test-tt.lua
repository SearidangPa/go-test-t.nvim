local M = {}

M.test_track_list = function()
  local terminal_test = require 'terminal_test'
  local tracker = require 'tracker'

  local make_notify = require('mini.notify').make_notify {}
  for _, test_info in ipairs(tracker.test_tracker) do
    make_notify(string.format('Running test: %s', test_info.test_name)).go_test_command(test_info)
    terminal_test.go_test_command(test_info)
  end
end

M.setup = function()
  local terminal_test = require 'terminal_test'
  vim.api.nvim_create_user_command('GoTestSearch', function() M.terminals_tests:search_terminal() end, {})
  vim.api.nvim_create_user_command('GoTestDelete', function() M.terminals_tests:select_delete_terminal() end, {})
  vim.api.nvim_create_user_command('GoTestNormalBuf', terminal_test.test_normal_buf, {})
  vim.api.nvim_create_user_command('GoTestNormal', terminal_test.go_normal_test, {})
  vim.api.nvim_create_user_command('GoTestDriveDev', terminal_test.drive_test_dev, {})
  vim.api.nvim_create_user_command('GoTestDriveStaging', terminal_test.drive_test_staging, {})
  vim.api.nvim_create_user_command('GoTestDriveStagingBuf', terminal_test.drive_test_staging_buf, {})
  vim.api.nvim_create_user_command('GoTestDriveDevBuf', terminal_test.drive_test_dev_buf, {})
  vim.api.nvim_create_user_command('GoTestWindowsBuf', terminal_test.windows_test_buf, {})
  vim.api.nvim_create_user_command('GoTestIntegration', terminal_test.go_integration_test, {})

  vim.keymap.set('n', '<leader>G', terminal_test.go_integration_test, { desc = 'Go integration test' })
  vim.keymap.set('n', '<leader>st', function() M.terminals_tests:search_terminal() end, { desc = 'Select test terminal' })
  vim.keymap.set('n', '<leader>tg', terminal_test.toggle_view_enclosing_test, { desc = 'Toggle go test terminal' })
  vim.keymap.set('n', '<leader>tl', terminal_test.toggle_last_test, { desc = 'Toggle last go test terminal' })

  require 'test_all'

  require 'tracker'
end

return M
