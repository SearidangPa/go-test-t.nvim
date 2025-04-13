---@class GoTestT
local go_test_t = {}
go_test_t.__index = go_test_t

---@param opts GoTestT.Options
function go_test_t.new(opts)
  opts = opts or {}
  local self = setmetatable({}, go_test_t)

  self.test_command_format_json = opts.test_command_format_json or 'go test ./... --json -v -run %s\r'
  self.job_id = -1
  self.tests_info = {}

  local term_test_command_format = opts.term_test_command_format or 'go test ./... -v -run %s\r'
  self.term_test = require('terminal_test.terminal_test').new {
    term_test_command_format = term_test_command_format,
  }
  self.test_displayer = require('display').new {
    display_title = opts.display_title or 'Go Test All Results',
    toggle_term_func = function(test_name) self.term_test:toggle_test_in_term(test_name) end,
    rerun_in_term_func = function(test_name) self.term_test:retest_in_terminal_by_name(test_name) end,
  }
  return self
end

function go_test_t:run_test_all()
  self.test_displayer:create_window_and_buf()

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
          vim.schedule(function() self_ref.test_displayer:update_buffer(self_ref.tests_info) end)
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
          vim.schedule(function() self_ref.test_displayer:update_buffer(self_ref.tests_info) end)
          goto continue
        end

        ::continue::
      end
    end,

    on_exit = function()
      vim.schedule(function() self_ref.test_displayer:update_buffer(self_ref.tests_info) end)
    end,
  })
end

function go_test_t:toggle_display() self.test_displayer:toggle_display() end
function go_test_t:load_stuck_tests() require('util_quickfix').load_non_passing_tests_to_quickfix(self.tests_info) end

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
    require('util_quickfix').add_fail_test(test_info)
    test_info.fidget_handle:finish()
  end
  self.tests_info[entry.Test] = test_info
  self.test_displayer:update_buffer(self.tests_info)
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
    require('util_quickfix').add_fail_test(test_info)
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

function go_test_t:_setup_commands()
  local self_ref = self
  vim.api.nvim_create_user_command('GoTestToggleDisplay', function() self_ref:toggle_display() end, {})
  vim.api.nvim_create_user_command('GoTestLoadStuckTest', function() self_ref:load_stuck_tests() end, {})
end

return go_test_t
