local fidget = require 'fidget'

---@class GoTestT
local go_test_t = {}
go_test_t.__index = go_test_t

---@param opts GoTestT.Options
function go_test_t.new(opts)
  opts = opts or {}
  local self = setmetatable({}, go_test_t)

  self.test_command_format = opts.test_command_format or 'go test ./... --json -v %s\r'
  self.job_id = -1
  self.tests_info = {}
  self.terminal_name = opts.terminal_name or 'go_test_t'
  self.ns_id = vim.api.nvim_create_namespace 'GoTestT'

  self.term_tester = require('terminal_test.terminal_test').new {
    term_test_command_format = self.test_command_format,
  }
  local user_command_prefix = opts.user_command_prefix or 'Go'
  self:setup_user_command(user_command_prefix)
  return self
end

function go_test_t:setup_user_command(user_command_prefix)
  local this = self
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestAll', function() this:test_all() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestToggleDisplay', function() this:toggle_display() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestLoadQuackTestQuickfix', function() this:load_quack_tests() end, {})

  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTerm', function() this.term_tester:test_nearest_in_terminal() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermBuf', function() this.term_tester:test_buf_in_terminals() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermView', function() this.term_tester:view_enclosing_test_terminal() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermSearch', function() this.term_tester.terminals:search_terminal() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermViewLast', function() this.term_tester:view_last_test_terminal() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermToggleDisplay', function() this.term_tester.term_test_displayer:toggle_display() end, {})
end

function go_test_t:test_all()
  self.term_tester.term_test_displayer:create_window_and_buf()
  local all_command = 'go test ./integration_tests/ -v\r'
  self.term_tester.terminals:delete_terminal(self.terminal_name)
  local float_term_state = self.term_tester.terminals:toggle_float_terminal(self.terminal_name)
  vim.api.nvim_chan_send(float_term_state.chan, all_command .. '\n')

  local self_ref = self
  vim.schedule(function()
    vim.api.nvim_buf_attach(float_term_state.buf, false, {
      on_lines = function(_, buf, _, first_line, last_line) return self_ref:_process_buffer_lines(buf, first_line, last_line) end,
    })
  end)
end

--- === Private functions ===

-- Process terminal output for all tests run
function go_test_t:_process_buffer_lines(buf, first_line, last_line)
  local lines = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)

  for _, line in ipairs(lines) do
    local test_name = line:match '=== RUN%s+([^%s]+)'
    if test_name then
      local test_info = self.tests_info[test_name] or {
        name = test_name,
        status = 'running',
      }
      self.tests_info[test_name] = test_info
      vim.schedule(function() self.term_tester.term_test_displayer:update_buffer(self.tests_info) end)
    end

    local pass_test = line:match '--- PASS:%s+([^%s]+)'
    if pass_test then
      local test_info = self.tests_info[pass_test] or {
        name = pass_test,
      }
      test_info.status = 'pass'
      self.tests_info[pass_test] = test_info
      vim.schedule(function()
        self.term_tester.term_test_displayer:update_buffer(self.tests_info)
        fidget.notify(string.format('%s passed', pass_test), vim.log.levels.INFO)
      end)
    end

    local fail_test = line:match '--- FAIL:%s+([^%s]+)'
    if fail_test then
      local test_info = self.tests_info[fail_test] or {
        name = fail_test,
      }
      test_info.status = 'fail'
      self.tests_info[fail_test] = test_info
      vim.schedule(function()
        self.term_tester.term_test_displayer:update_buffer(self.tests_info)
        fidget.notify(string.format('%s failed', fail_test), vim.log.levels.ERROR)
      end)
    end

    local error_test, error_file, error_line = line:match '(.+):%s+([^:]+):(%d+):%s+'
    if error_test and error_file and error_line then
      for test_info_name, test_info in pairs(self.tests_info) do
        if error_test:find(test_info_name, 1, true) then
          test_info.fail_at_line = tonumber(error_line)
          test_info.filepath = error_file
          test_info.status = 'fail'
          self.tests_info[test_info_name] = test_info
          require('util_go_test_quickfix').add_fail_test(test_info)
          vim.schedule(function() self.term_tester.term_test_displayer:update_buffer(self.tests_info) end)
          break
        end
      end
    end
  end
end

function go_test_t:_validate_test_info(test_info)
  assert(test_info.name, 'No test found')
  assert(test_info.test_bufnr, 'No test buffer found')
  assert(test_info.test_line, 'No test line found')
  assert(test_info.test_command, 'No test command found')
  assert(vim.api.nvim_buf_is_valid(test_info.test_bufnr), 'Invalid buffer')
end
