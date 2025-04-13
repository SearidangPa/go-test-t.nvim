local display = require 'go-test-t-display'
local util_quickfix = require 'async_job.util_quickfix'
local fidget = require 'fidget'
local terminal_test = require 'terminal_test.terminal_test'

---@class GoTesties
local Go_testies_M = {}
Go_testies_M.__index = Go_testies_M

function Go_testies_M.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Go_testies_M)
  local test_command_format = opts.test_command_format or 'go test ./... -v -run %s\r'

  self.term_test = terminal_test.new {
    test_command_format = test_command_format,
  }

  self.job_id = -1
  self.tests_info = {}
  self.test_displayer = display.new {
    display_title = opts.display_title or 'Go Test All Results',
    toggle_term_func = function(test_name) self.term_test:toggle_test_in_term(test_name) end,
    rerun_in_term_func = function(test_name) self.term_test:retest_in_terminal_by_name(test_name) end,
  }
  return self
end

function Go_testies_M:run_test_all()
  self.test_displayer:create_window_and_buf()

  self:_clean_up_prev_job()
  local self_ref = self
  self.job_id = vim.fn.jobstart(self.test_command_format, {
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

function Go_testies_M:toggle_display() self.test_displayer:toggle_display() end
function Go_testies_M:load_stuck_tests() util_quickfix.load_non_passing_tests_to_quickfix(self.tests_info) end

function Go_testies_M:_setup_commands()
  local self_ref = self
  vim.api.nvim_create_user_command('GoTestToggleDisplay', function() self_ref:toggle_display() end, {})
  vim.api.nvim_create_user_command('GoTestLoadStuckTest', function() self_ref:load_stuck_tests() end, {})
end

--- === Private functions ===
function Go_testies_M:_clean_up_prev_job()
  if self.job_id ~= -1 then
    fidget.notify('Stopping job', vim.log.levels.INFO)
    vim.fn.jobstop(self.job_id)
    vim.diagnostic.reset()
  end
end

function Go_testies_M:_add_golang_test(entry)
  if not entry.Test then
    return
  end

  local test_info = {
    name = entry.Test,
    status = 'running',
    filepath = '',
    fidget_handle = fidget.progress.handle.create {
      lsp_client = {
        name = entry.Test,
      },
    },
  }

  self.tests_info[entry.Test] = test_info
end

function Go_testies_M:_filter_golang_output(entry)
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
    util_quickfix.add_fail_test(test_info)
    test_info.fidget_handle:finish()
  end
  self.tests_info[entry.Test] = test_info
  self.test_displayer:update_buffer(self.tests_info)
end

function Go_testies_M:_mark_outcome(entry)
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
    util_quickfix.add_fail_test(test_info)
    test_info.fidget_handle:finish()
  elseif entry.Action == 'pass' then
    test_info.fidget_handle:finish()
  end
end

Go_testies_M._ignored_actions = {
  skip = true,
}

Go_testies_M._action_state = {
  pause = true,
  cont = true,
  start = true,
  fail = true,
  pass = true,
}

return Go_testies_M
