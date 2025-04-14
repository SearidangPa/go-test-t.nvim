---@class GoTestT
local go_test_t = {}
go_test_t.__index = go_test_t

---@param opts GoTestT.Options
function go_test_t.new(opts)
  opts = opts or {}
  local self = setmetatable({}, go_test_t)

  self.test_command_format_json = opts.test_command_format_json or 'go test ./... --json -v %s\r'
  self.job_id = -1
  self.tests_info = {}

  local term_test_command_format = opts.term_test_command_format or 'go test ./... -v -run %s\r'
  self.term_tester = require('terminal_test.terminal_test').new {
    term_test_command_format = term_test_command_format,
  }
  self.go_test_displayer = require('util_go_test_display').new {
    display_title = opts.display_title or 'Go Test All Results',
    toggle_term_func = function(test_name) self.term_tester:toggle_test_in_term(test_name) end,
    rerun_in_term_func = function(test_name) self.term_tester:retest_in_terminal_by_name(test_name) end,
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

  -- ---@type TerminalTestTracker
  -- local tracker = require 'terminal_test.tracker'
  -- local map = vim.keymap.set
  -- map('n', '<leader>tr', tracker.toggle_tracker_window, { desc = '[A]dd [T]est to tracker' })
  -- map('n', '<leader>at', function() tracker.add_test_to_tracker 'go test ./... -v -run %s' end, { desc = '[A]dd [T]est to tracker' })
end

function go_test_t:test_all()
  self.go_test_displayer:create_window_and_buf()

  self:_clean_up_prev_job()
  local self_ref = self
  self.job_id = vim.fn.jobstart(self.test_command_format_json, {
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
          vim.schedule(function() self_ref.go_test_displayer:update_buffer(self_ref.tests_info) end)
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
          vim.schedule(function() self_ref.go_test_displayer:update_buffer(self_ref.tests_info) end)
          goto continue
        end

        ::continue::
      end
    end,

    on_exit = function()
      vim.schedule(function() self_ref.go_test_displayer:update_buffer(self_ref.tests_info) end)
    end,
  })
end

function go_test_t:toggle_display() self.go_test_displayer:toggle_display() end
function go_test_t:load_quack_tests() require('util_go_test_quickfix').load_non_passing_tests_to_quickfix(self.tests_info) end

--- === Private functions ===
function go_test_t:_clean_up_prev_job()
  if self.job_id ~= -1 then
    require('fidget').notify('Stopping job', vim.log.levels.INFO)
    vim.fn.jobstop(self.job_id)
    vim.diagnostic.reset()
  end
end

function go_test_t:_add_golang_test(entry)
  if not entry.Test then
    return
  end

  local test_info = {
    name = entry.Test,
    status = 'running',
    filepath = '',
    fidget_handle = require('fidget').progress.handle.create {
      lsp_client = {
        name = entry.Test,
      },
    },
  }

  self.tests_info[entry.Test] = test_info
end

function go_test_t:_filter_golang_output(entry)
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
    require('util_go_test_quickfix').add_fail_test(test_info)
    test_info.fidget_handle:finish()
  end
  self.tests_info[entry.Test] = test_info
  self.go_test_displayer:update_buffer(self.tests_info)
end

function go_test_t:_mark_outcome(entry)
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
    test_info.fidget_handle:finish()
  elseif entry.Action == 'pass' then
    test_info.fidget_handle:finish()
  end
end

go_test_t._ignored_actions = {
  skip = true,
}

go_test_t._action_state = {
  pause = true,
  cont = true,
  start = true,
  fail = true,
  pass = true,
}

return go_test_t
