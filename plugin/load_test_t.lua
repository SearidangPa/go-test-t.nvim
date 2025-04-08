vim.api.nvim_create_user_command('ReloadTestT', function()
  -- Easy Reloading
  package.loaded['test-t'] = nil
  require('test-t').setup()
end, {})
