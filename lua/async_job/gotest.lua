local display = require 'display'
local util_quickfix = require 'async_job.util_quickfix'
local fidget = require 'fidget'

local tests_info = {}

---@type Gotest
local go_test = {
  job_id = -1,
}
go_test.displayer = display.new(tests_info)

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
  local key = entry.Test
  tests_info[key] = {
    name = entry.Test,
    fail_at_line = 0,
    output = {},
    status = 'running',
    filepath = '',
  }
end

local filter_golang_output = function(entry)
  assert(entry, 'No entry provided')
  if not entry.Test then
    return ''
  end
  local test_info = tests_info[entry.Test]
  if not test_info then
    vim.notify('Filter Output: Test info not found for ' .. entry.Test, vim.log.levels.WARN)
    return
  end

  local trimmed_output = vim.trim(entry.Output)
  if trimmed_output:match '^--- FAIL:' then
    local file, line = string.match(trimmed_output, '([%w_%-]+%.go):(%d+):')
    if file and line then
      local line_num = tonumber(line)
      assert(line_num, 'Line number must be a number')
      test_info.fail_at_line = line_num
      test_info.filepath = file
    end
    test_info.status = 'fail'
    util_quickfix.add_fail_test(test_info)
  end
end

local mark_outcome = function(entry)
  if not entry.Test then
    return ''
  end
  local key = entry.Test
  local test_info = tests_info[key]
  if not test_info then
    return
  end

  test_info.status = entry.Action
  tests_info[key] = test_info
  if entry.Action == 'fail' then
    util_quickfix.add_fail_test(test_info)
    fidget.notify(string.format('%s failed', test_info.name), vim.log.levels.WARN)
  elseif entry.Action == 'pass' then
    fidget.notify(string.format('%s passed', test_info.name), vim.log.levels.INFO)
  end
end

go_test.run_test_all = function(command)
  tests_info = {}
  go_test.displayer:setup(tests_info)
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
          vim.schedule(function() go_test.displayer:update_tracker_buffer(tests_info) end)
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
          vim.schedule(function() go_test.displayer:update_tracker_buffer(tests_info) end)
          goto continue
        end

        ::continue::
      end
    end,

    on_exit = function()
      vim.schedule(function() go_test.displayer:update_tracker_buffer(tests_info) end)
    end,
  })
end

vim.api.nvim_create_user_command('GoTestAll', function()
  local command = { 'go', 'test', './...', '-json', '-v' }
  go_test.run_test_all(command)
end, {})

vim.api.nvim_create_user_command('GoTestToggleDisplay', function() go_test.displayer:toggle_display() end, {})
vim.api.nvim_create_user_command('GoTestLoadStuckTest', function() util_quickfix.load_non_passing_tests_to_quickfix(tests_info) end, {})
return go_test
