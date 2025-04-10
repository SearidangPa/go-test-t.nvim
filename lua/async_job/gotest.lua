-- local make_notify = require('mini.notify').make_notify {}
local display = require 'go_display'
local util_quickfix = require 'async_job.util_quickfix'
local displayer = display.new()
local fidget = require 'fidget'

local gotest = {
  tests_info = {}, ---@type gotest.TestInfo[]
  job_id = -1, ---@type number
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

gotest.clean_up_prev_job = function(job_id)
  if job_id ~= -1 then
    fidget.notify('Stopping job', vim.log.levels.INFO)
    vim.fn.jobstop(job_id)
    vim.diagnostic.reset()
  end
end

---@param tests_info gotest.TestInfo[]
local add_golang_test = function(tests_info, entry)
  if not entry.Test then
    return ''
  end
  local key = entry.Test
  tests_info[key] = {
    name = entry.Test,
    fail_at_line = 0,
    output = {},
    status = 'running',
    file = '',
  }
end

---@param tests_info gotest.TestInfo[]
local add_golang_output = function(tests_info, entry)
  assert(tests_info, vim.inspect(tests_info))
  if not entry.Test then
    return ''
  end
  local key = entry.Test
  local test_info = tests_info[key]
  if not test_info then
    return
  end
  local trimmed_output = vim.trim(entry.Output)
  local file, line = string.match(trimmed_output, '([%w_%-]+%.go):(%d+):')
  if file and line then
    local line_num = tonumber(line)
    assert(line_num, 'Line number must be a number')
    test_info.fail_at_line = line_num
    test_info.file = file
  end
  if trimmed_output:match '^--- FAIL:' then
    test_info.status = 'fail'
    util_quickfix.add_fail_test(test_info)
  end
end

---@param tests_info gotest.TestInfo[]
local mark_outcome = function(tests_info, entry)
  if not entry.Test then
    return ''
  end
  local key = entry.Test
  local test_info = tests_info[key]
  if not test_info then
    return
  end
  test_info.status = entry.Action
  if entry.Action == 'fail' then
    util_quickfix.add_fail_test(test_info)
    fidget.notify(string.format('%s failed', test_info.name), vim.log.levels.WARN)
    vim.notify(string.format('Added failed test to quickfix: %s', test_info.name), vim.log.levels.WARN)
  elseif entry.Action == 'pass' then
    fidget.notify(string.format('%s passed', test_info.name), vim.log.levels.INFO)
  end
end

gotest.run_test_all = function(command)
  gotest.tests_info = {}
  displayer:setup(gotest.tests_info)
  gotest.clean_up_prev_job(gotest.job_id)
  gotest.job_id = vim.fn.jobstart(command, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      assert(data, 'No data received from job')
      for _, line in ipairs(data) do
        if line == '' then
          goto continue
        end
        local success, decoded = pcall(vim.json.decode, line)
        if not success or not decoded then
          goto continue
        end
        if ignored_actions[decoded.Action] then
          goto continue
        end
        if decoded.Action == 'run' then
          add_golang_test(gotest.tests_info, decoded)
          vim.schedule(function() displayer:update_tracker_buffer(gotest.tests_info) end)
          goto continue
        end
        if decoded.Action == 'output' then
          if decoded.Test or decoded.Package then
            add_golang_output(gotest.tests_info, decoded)
          end
          goto continue
        end
        if action_state[decoded.Action] then
          mark_outcome(gotest.tests_info, decoded)
          vim.schedule(function() displayer:update_tracker_buffer(gotest.tests_info) end)
          goto continue
        end
        ::continue::
      end
    end,
    on_exit = function()
      vim.schedule(function() displayer:update_tracker_buffer(gotest.tests_info) end)
    end,
  })
end

vim.api.nvim_create_user_command('GoTestAll', function()
  local command = { 'go', 'test', './...', '-json', '-v' }
  gotest.run_test_all(command)
end, {})

vim.api.nvim_create_user_command('GoTestToggleDisplay', function() displayer:toggle_display() end, {})
vim.api.nvim_create_user_command('GoTestLoadStuckTest', function() util_quickfix.load_non_passing_tests_to_quickfix(gotest.tests_info) end, {})
return gotest
