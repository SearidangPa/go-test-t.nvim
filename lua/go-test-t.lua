local M = {}

M.setup = function()
  require 'async_job.go_test'
  require 'terminal_test.tracker'
  require 'terminal_test.terminal_test'

  vim.api.nvim_create_user_command('ReloadTestT', function()
    local modules = {
      'display',
      'go-test-t',
      'util_find_test',
      'util_status_icon',
      'terminal_test.terminal_multiplexer',
      'terminal_test.terminal_test',
      'terminal_test.tracker',
      'async_job.go_test',
      'async_job.util_quickfix',
    }

    for _, cmd in ipairs {
      'TerminalTest',
      'TerminalTestBuf',
    } do
      if vim.fn.exists(':' .. cmd) > 0 then
        vim.cmd('delcommand ' .. cmd)
      end
    end

    for _, module in ipairs(modules) do
      package.loaded[module] = nil
    end

    vim.notify('Terminal test plugin reloaded', vim.log.levels.INFO)
  end, {})
end

return M
