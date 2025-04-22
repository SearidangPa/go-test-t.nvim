---@class GoTestT
local go_test = {}
go_test.__index = go_test

---@param opts GoTestT.Options
function go_test.new(opts)
  opts = opts or {}
  local self = setmetatable({}, go_test)
  self.go_test_prefix = opts.go_test_prefix or 'go test'

  self.job_id = -1
  self.tests_info = {}
  self.terminal_name = opts.terminal_name or 'test all'
  self.ns_id = vim.api.nvim_create_namespace 'GoTestT'

  self.pin_tester = require('terminal_test.pin_test').new {
    go_test_prefix = self.go_test_prefix,
    update_buffer_func = function(tests_info) self.term_tester.displayer:update_buffer(tests_info) end,
    toggle_display_func = function() self.term_tester.displayer:toggle_display() end,
    test_in_terminal_func = function(test_info) self.term_tester:test_in_terminal(test_info) end,
    test_nearest_in_terminal_func = function() return self.term_tester:test_nearest_in_terminal() end,
  }

  self.term_tester = require('terminal_test.terminal_test').new {
    go_test_prefix = self.go_test_prefix,
    tests_info = self.tests_info,
    pin_test_func = function(test_info) self.pin_tester:pin_test(test_info) end,
    display_title = 'Go Test Results',
    is_test_pinned_func = function(test_name) return self.pin_tester:is_test_pinned(test_name) end,
    get_test_info_func = function(test_name) return self.tests_info[test_name] end,
    add_test_info_func = function(test_info)
      self.tests_info[test_info.name] = test_info
      vim.schedule(function() self.term_tester.displayer:update_buffer(self.tests_info) end)
    end,
  }
  local user_command_prefix = opts.user_command_prefix or ''
  self:setup_user_command(user_command_prefix)
  return self
end

function go_test:setup_user_command(user_command_prefix)
  local term_tester = self.term_tester
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestReset', function()
    term_tester:reset()
    self:reset()
  end, {})

  vim.api.nvim_create_user_command(user_command_prefix .. 'TestAll', function() self:test_all(false) end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestPkg', function() self:test_all(true) end, {})
  vim.api.nvim_create_user_command(
    user_command_prefix .. 'TestAllView',
    function() self.term_tester.terminals:toggle_float_terminal(self.terminal_name) end,
    {}
  )
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestToggleDisplay', function() term_tester.displayer:toggle_display() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestLoadQuackTestQuickfix', function() self:load_quack_tests() end, {})

  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTerm', function() term_tester:test_nearest_in_terminal() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermBuf', function() term_tester:test_buf_in_terminals() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermView', function() term_tester:test_nearest_with_view_term() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermSearch', function() term_tester.terminals:search_terminal() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestTermViewLast', function() term_tester:toggle_last_test_terminal() end, {})

  vim.api.nvim_create_user_command(user_command_prefix .. 'PinTest', function() self.pin_tester:pin_nearest_test() end, {})
  vim.api.nvim_create_user_command(user_command_prefix .. 'TestAllPinned', function() self.pin_tester:test_all_pinned() end, {})
end

function go_test:test_all(test_in_pkg_only)
  test_in_pkg_only = test_in_pkg_only or false
  local test_command
  if test_in_pkg_only then
    local util_path = require 'util_path'
    local intermediate_path = util_path.get_intermediate_path()
    test_command = string.format('%s %s -v --json', self.go_test_prefix, intermediate_path)
  else
    test_command = string.format('%s ./... -v --json', self.go_test_prefix)
  end

  self:reset()
  self.term_tester.displayer:create_window_and_buf()

  self:_clean_up_prev_job()
  local self_ref = self
  self.job_id = vim.fn.jobstart(test_command, {
    stdout_buffered = false,

    on_stdout = function(_, data)
      assert(data, 'No data received from job')
      for _, line in ipairs(data) do
        if line == '' then
          goto continue
        end

        local ok, decoded = pcall(vim.json.decode, line)
        if not ok or not decoded then
          goto continue
        end

        if self._ignored_actions[decoded.Action] then
          goto continue
        end

        if decoded.Action == 'run' then
          self_ref:_add_golang_test(decoded)
          self_ref.term_tester.displayer:update_buffer(self_ref.tests_info)
          goto continue
        end

        if decoded.Action == 'output' then
          if decoded.Test or decoded.Package then
            self_ref:_filter_golang_output(decoded)
          end
          goto continue
        end

        if self._action_state[decoded.Action] then
          self_ref:_mark_outcome(decoded)
          self_ref.term_tester.displayer:update_buffer(self_ref.tests_info)
          goto continue
        end

        ::continue::
      end
    end,

    on_exit = function() end,
  })
end

function go_test:toggle_display() self.term_tester.displayer:toggle_display() end
function go_test:load_quack_tests() require('util_go_test_quickfix').load_non_passing_tests_to_quickfix(self.tests_info) end

function go_test:reset()
  self.job_id = -1
  self.tests_info = {}
  self.term_tester:reset()
  self.term_tester.displayer:reset()
end

--- === Private functions ===

function go_test:_clean_up_prev_job()
  if self.job_id ~= -1 then
    require('fidget').notify('Stopping job', vim.log.levels.INFO)
    vim.fn.jobstop(self.job_id)
    vim.diagnostic.reset()
  end
end

function go_test:_add_golang_test(entry)
  if not entry.Test then
    return
  end

  local test_info = {
    name = entry.Test,
    status = 'running',
    filepath = '',
  }

  self.tests_info[entry.Test] = test_info
  self.term_tester.tests_info[entry.Test] = test_info
  self.term_tester.displayer:update_buffer(self.tests_info)
end

function go_test:_filter_golang_output(entry)
  assert(entry, 'No entry provided')
  if not entry.Test then
    return
  end
  local test_info = self.tests_info[entry.Test]
  if not test_info then
    vim.notify('Filter Output: Test info not found for ' .. entry.Test, vim.log.levels.WARN)
    return
  end

  local trimmed_output = vim.trim(entry.Output)

  local file, line_num_any = string.match(trimmed_output, 'Error Trace:%s+([^:]+):(%d+)')
  if file and line_num_any then
    local line_num = tonumber(line_num_any)
    assert(line_num, 'Line number must be a number')
    test_info.fail_at_line = line_num
    test_info.filepath = file
  end

  if trimmed_output:match '^--- FAIL:' then
    test_info.status = 'fail'
    self.pin_tester:pin_test(test_info)
    require('util_go_test_quickfix').add_fail_test(test_info)
  end
  self.tests_info[entry.Test] = test_info
  self.term_tester.displayer:update_buffer(self.tests_info)
end

function go_test:_mark_outcome(entry)
  if not entry.Test then
    return
  end
  local key = entry.Test
  local test_info = self.tests_info[key]
  if not test_info then
    return
  end

  test_info.status = entry.Action
  self.tests_info[key] = test_info
  if entry.Action == 'fail' then
    require('util_go_test_quickfix').add_fail_test(test_info)
    local make_notify = require('mini.notify').make_notify {}
    make_notify(string.format('pinning %s', test_info.name), vim.log.levels.ERROR)
    self.pin_tester:pin_test(test_info)
  end
end

go_test._ignored_actions = {
  skip = true,
}

go_test._action_state = {
  pause = true,
  cont = true,
  start = true,
  fail = true,
  pass = true,
}

return go_test
