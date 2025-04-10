-- Easy Reloading
vim.api.nvim_create_user_command('ReloadTestT', function()
  package.loaded['display'] = nil
  package.loaded['go-test-tt'] = nil
  package.loaded['util_find_test'] = nil
  package.loaded['util_status_icon'] = nil
  package.loaded['annotation'] = nil
  package.loaded['terminal_multiplexer'] = nil
  package.loaded['terminal_test'] = nil
  package.loaded['tracker'] = nil
  package.loaded['gotest'] = nil
  package.loaded['util_quickfix'] = nil
  require('go-test-tt').setup()
end, {})
