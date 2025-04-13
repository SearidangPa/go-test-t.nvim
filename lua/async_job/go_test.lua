local display = require 'go-test-t-display'
local util_quickfix = require 'async_job.util_quickfix'
local fidget = require 'fidget'

local terminal_test = require 'terminal_test.terminal_test'
local term_test = terminal_test.new {
  test_command_format = 'go test ./... -v -run %s\r', -- TODO: make this configurable
}

---@type Gotest
local go_test = {
  job_id = -1,
  tests_info = {},
  test_displayer = display.new {
    display_title = 'Go Test All Results',
    toggle_term_func = function(test_name) term_test.terminals:toggle_float_terminal(test_name) end,
    rerun_in_term_func = function(test_name) term_test:retest_in_terminal_by_name(test_name) end,
  },
}

local ignored_actions = {
  skip = true,
}

local action_state = {
  pause = true,
  cont = true,
  start = true,
  fail = true,
  pass = true,
}

go_test.clean_up_prev_job = function(job_id)
  if job_id ~= -1 then
    fidget.notify('Stopping job', vim.log.levels.INFO)
    vim.fn.jobstop(job_id)
    vim.diagnostic.reset()
  end
end

local function add_golang_test(entry)
  if not entry.Test then
    return ''
  end

  ---@type gotest.TestInfo
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

  go_test.tests_info[entry.Test] = test_info
end

local function filter_golang_output(entry)
  assert(entry, 'No entry provided')
  if not entry.Test then
    return ''
  end
  local test_info = go_test.tests_info[entry.Test]
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
  go_test.tests_info[entry.Test] = test_info
  go_test.test_displayer:update_buffer(go_test.tests_info)
end

local function mark_outcome(entry)
  if not entry.Test then
    return ''
  end
  local key = entry.Test
  local test_info = go_test.tests_info[key]
  if not test_info then
    return
  end

  test_info.status = entry.Action
  go_test.tests_info[key] = test_info
  if entry.Action == 'fail' then
    util_quickfix.add_fail_test(test_info)
    test_info.fidget_handle:finish()
  elseif entry.Action == 'pass' then
    test_info.fidget_handle:finish()
  end
end

go_test.run_test_all = function(command)
  go_test.test_displayer:create_window_and_buf()

  go_test.clean_up_prev_job(go_test.job_id)
  go_test.job_id = vim.fn.jobstart(command, {
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

        if ignored_actions[decoded.Action] then
          goto continue
        end

        if decoded.Action == 'run' then
          add_golang_test(decoded)
          vim.schedule(function() go_test.test_displayer:update_buffer(go_test.tests_info) end)
          goto continue
        end

        if decoded.Action == 'output' then
          if decoded.Test or decoded.Package then
            filter_golang_output(decoded)
          end
          goto continue
        end

        if action_state[decoded.Action] then
          mark_outcome(decoded)
          vim.schedule(function() go_test.test_displayer:update_buffer(go_test.tests_info) end)
          goto continue
        end

        ::continue::
      end
    end,

    on_exit = function()
      vim.schedule(function() go_test.test_displayer:update_buffer(go_test.tests_info) end)
    end,
  })
end

vim.api.nvim_create_user_command('GoTestAll', function()
  local command = { 'go', 'test', './...', '-json', '-v' }
  go_test.run_test_all(command)
end, {})

vim.api.nvim_create_user_command('GoTestToggleDisplay', function() go_test.test_displayer:toggle_display() end, {})
vim.api.nvim_create_user_command('GoTestLoadStuckTest', function() util_quickfix.load_non_passing_tests_to_quickfix(go_test.tests_info) end, {})
return go_test
