---@class GoTestT
local go_test = {
  ---@class GoTestT
  the_go_test_t = nil,
}
go_test.__index = go_test


function go_test.setup(opts) go_test.the_go_test_t = go_test.new(opts) end

---@param opts GoTestT.Options
function go_test.new(opts)
  opts = opts or {}
  local self = setmetatable({}, go_test)
  self.go_test_prefix = opts.go_test_prefix or 'go test'
  self.integration_test_pkg = opts.integration_test_pkg

  self.job_id = -1
  self.tests_info = {}
  self.go_test_ns_id = vim.api.nvim_create_namespace 'GoTestT'

  self.pin_tester = require('go-test-t.pin_test').new {
    update_display_buffer_func = function(tests_info) self.displayer:update_display_buffer(tests_info) end,
    toggle_display_func = function(do_not_close) self.displayer:toggle_display(do_not_close) end,
    retest_in_terminal_by_name = function(test_name) self.term_tester:retest_in_terminal_by_name(test_name) end,
    test_nearest_in_terminal_func = function() return self.term_tester:test_nearest_in_terminal() end,
    add_test_info_func = function(test_info) self.tests_info[test_info.name] = test_info end,
  }

  self.displayer = require('go-test-t.test_board').new {
    display_title = 'Go Test Results',
    rerun_in_term_func = function(test_name) self.term_tester:retest_in_terminal_by_name(test_name) end,
    get_tests_info_func = function() return self.tests_info end,
    get_pinned_tests_func = function() return self.pin_tester.pinned_list end,
    preview_terminal_func = function(test_name) return self.term_tester:preview_terminal(test_name) end,
  }

  self.term_tester = require('go-test-t.test_terminal').new {
    go_test_prefix = self.go_test_prefix,
    tests_info = self.tests_info,
    pin_test_func = function(test_info) self.pin_tester:pin_test(test_info) end,
    get_pinned_tests_func = function() return self.pin_tester.pinned_list end,
    get_test_info_func = function(test_name) return self.tests_info[test_name] end,
    add_test_info_func = function(test_info) self.tests_info[test_info.name] = test_info end,
    ns_id = vim.api.nvim_create_namespace 'Terminal Test',
    toggle_display_func = function(do_not_close) self.displayer:toggle_display(do_not_close) end,
    update_display_buffer_func = function(tests_info) self.displayer:update_display_buffer(tests_info) end,
  }
  self:setup_user_command()
  return self
end

---@param opts GoTestT.Options
function go_test:set_go_test_prefix(opts)
  assert(type(opts) == 'table', 'Options must be a table')
  assert(opts.go_test_prefix, 'go_test_prefix must be provided in options')
  local new_prefix = opts.go_test_prefix
  local self_ref = self
  self_ref.go_test_prefix = new_prefix
  self_ref.term_tester.go_test_prefix = new_prefix
end

function go_test.test_this()
  local the_go_test_t = go_test.the_go_test_t
  local util_find_test = require 'go-test-t.util_find_test'
  local test_name, _ = util_find_test.get_enclosing_test()
  if not test_name then
    local last_test = the_go_test_t.term_tester.terminal_multiplexer.last_terminal_name
    if last_test then
      local test_info = the_go_test_t.term_tester.get_test_info_func(last_test)
      the_go_test_t.term_tester:test_in_terminal(test_info, true)
    end
  else
    the_go_test_t.term_tester:test_nearest_in_terminal()
  end
end

function go_test:setup_user_command()
  local self_ref = self
  vim.api.nvim_create_user_command('TestBoard',
    function() self_ref.displayer:toggle_display() end,
    {}
  )

  if self.integration_test_pkg and self.integration_test_pkg ~= '' then
    vim.api.nvim_create_user_command('TestIntegration',
      function() self_ref:test_pkg(self.integration_test_pkg) end,
      {}
    )
  end

  vim.api.nvim_create_user_command('TestReset', function()
    self_ref:reset_all()
    vim.notify('Go Test T: Reset all tests', vim.log.levels.INFO)
  end, { desc = 'Reset all tests' })
end

function go_test.test_file()
  local the_go_test_t = go_test.the_go_test_t
  the_go_test_t.term_tester:test_buf_in_terminals()
end

function go_test.go_to_test_location()
  local the_go_test_t = go_test.the_go_test_t
  local util_lsp = require 'go-test-t.util_lsp'
  local test_name = the_go_test_t.term_tester.terminal_multiplexer.last_terminal_name
  util_lsp.action_from_test_name(test_name, function(lsp_param)
    local filepath = lsp_param.filepath
    local test_line = lsp_param.test_line
    vim.cmd('edit ' .. filepath)

    if test_line then
      local pos = { test_line, 0 }
      vim.api.nvim_win_set_cursor(0, pos)
      vim.cmd 'normal! zz'
    end
  end)
end

function go_test.view_last_test_terminal()
  local the_go_test_t = go_test.the_go_test_t
  the_go_test_t.term_tester:toggle_last_test_terminal()
end

function go_test:reset_keep_pin()
  local self_ref = self
  self_ref.job_id = -1
  self_ref.tests_info = {}
  self_ref.term_tester:reset()
  self_ref.displayer:reset()
end

function go_test:reset_all()
  local self_ref = self
  self_ref:reset_keep_pin()
  self_ref.pin_tester.pinned_list = {}
end

---@param test_pkg? string
function go_test:test_pkg(test_pkg)
  local self_ref = self
  test_pkg = test_pkg or './...'
  local test_command = string.format('%s %s -v --json', self_ref.go_test_prefix, test_pkg)

  self_ref:reset_keep_pin()
  self_ref.displayer:create_window_and_buf()

  self_ref:_clean_up_prev_job()
  self_ref.job_id = vim.fn.jobstart(test_command, {
    stdout_buffered = false,
    stderr_buffered = false,

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

        if self_ref._ignored_actions[decoded.Action] then
          goto continue
        end

        if decoded.Action == 'run' then
          self_ref:_add_golang_test(decoded, test_command)
          self_ref.displayer:update_display_buffer()
          goto continue
        end

        if decoded.Action == 'output' then
          if decoded.Test or decoded.Package then
            self_ref:_filter_golang_output(decoded)
          end
          goto continue
        end

        if self_ref._action_state[decoded.Action] then
          self_ref:_mark_outcome(decoded)
          self_ref.displayer:update_display_buffer()
          goto continue
        end

        ::continue::
      end
    end,

    on_stderr = function(_, data)
      assert(data, 'No data received from job stderr')
      for _, line in ipairs(data) do
        if line ~= '' then
          vim.notify('Job stderr: ' .. line, vim.log.levels.ERROR)
        end
      end
    end,
    on_exit = function() end,
  })
end

--- === Private functions ===

function go_test:_clean_up_prev_job()
  local self_ref = self
  if self_ref.job_id ~= -1 then
    vim.notify('Stopping job', vim.log.levels.INFO)
    vim.fn.jobstop(self_ref.job_id)
    vim.diagnostic.reset()
  end
end

---@param entry table
function go_test:_add_golang_test(entry, test_command)
  local self_ref = self
  if not entry.Test then
    return
  end


  ---@type terminal.testInfo
  local test_info = {
    name = entry.Test,
    status = 'running',
    filepath = '',
    test_command = test_command,
    set_ext_mark = false,
    output = {},
  }

  self_ref.tests_info[entry.Test] = test_info
  vim.schedule(function() self_ref.displayer:update_display_buffer() end)
end

function go_test:_filter_golang_output(entry)
  local self_ref = self
  assert(entry, 'No entry provided')
  if not entry.Test then
    return
  end
  local test_info = self_ref.tests_info[entry.Test]
  if not test_info then
    vim.notify('Filter Output: Test info not found for ' .. entry.Test, vim.log.levels.WARN)
    return
  end

  local trimmed_output = vim.trim(entry.Output)

  table.insert(test_info.output, trimmed_output)

  local file, line_num_any = string.match(trimmed_output, 'Error Trace:%s+([^:]+):(%d+)')
  if file and line_num_any then
    local line_num = tonumber(line_num_any)
    assert(line_num, 'Line number must be a number')
    test_info.fail_at_line = line_num
    test_info.filepath = file
  end

  if trimmed_output:match '^--- FAIL:' then
    test_info.status = 'fail'
    self_ref.pin_tester:pin_test(test_info)
    require('go-test-t.util_quickfix').add_fail_test(test_info)
  end
  self_ref.tests_info[entry.Test] = test_info
  self_ref.displayer:update_display_buffer()
end

function go_test:_mark_outcome(entry)
  local self_ref = self
  if not entry.Test then
    return
  end
  local key = entry.Test
  local test_info = self_ref.tests_info[key]
  if not test_info then
    return
  end

  test_info.status = entry.Action
  self_ref.tests_info[key] = test_info
  if entry.Action == 'fail' then
    require('go-test-t.util_quickfix').add_fail_test(test_info)
    self_ref.pin_tester:pin_test(test_info)
    vim.schedule(function() self_ref.displayer:update_display_buffer() end)
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
