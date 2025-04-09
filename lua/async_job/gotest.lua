local M = {}
local make_notify = require('mini.notify').make_notify {}
local display = require 'async_job.display'

M.tests = {}
M.job_id = -1

---@class gotest.TestInfo
---@field name string
---@field package string
---@field full_name string
---@field fail_at_line number
---@field output string[]
---@field status string "running"|"pass"|"fail"|"paused"|"cont"|"start"
---@field file string

M.clean_up_prev_job = function(job_id)
  if job_id ~= -1 then
    make_notify(string.format('stopping job: %d', job_id))
    vim.fn.jobstop(job_id)
    vim.diagnostic.reset()
  end
end

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

local make_key = function(entry)
  assert(entry.Package, 'Must have package name' .. vim.inspect(entry))
  if not entry.Test then
    return entry.Package
  end
  assert(entry.Test, 'Must have test name' .. vim.inspect(entry))
  return string.format('%s/%s', entry.Package, entry.Test)
end

local add_golang_test = function(test_state, entry)
  local key = make_key(entry)
  test_state.tests[key] = {
    name = entry.Test or 'Package Test',
    package = entry.Package,
    full_name = key,
    fail_at_line = 0,
    output = {},
    status = 'running',
    file = '',
  }
end

local add_golang_output = function(tests, entry)
  assert(tests, vim.inspect(tests))
  local key = make_key(entry)
  local test = tests[key]

  if not test then
    return
  end

  local trimmed_output = vim.trim(entry.Output)
  table.insert(test.output, trimmed_output)

  local file, line = string.match(trimmed_output, '([%w_%-]+%.go):(%d+):')
  if file and line then
    test.fail_at_line = tonumber(line)
    test.file = file
  end

  if trimmed_output:match '^--- FAIL:' then
    test.status = 'fail'
  end
end

local mark_outcome = function(tests, entry)
  local key = make_key(entry)
  local test = tests[key]

  if not test then
    return
  end
  -- Explicitly set the status based on the Action
  test.status = entry.Action
end

M.run_test_all = function(command)
  -- Reset test state
  M.tests = {}

  -- Set up tracker buffer
  display.setup_display_buffer()

  -- Clean up previous job
  M.clean_up_prev_job(M.job_id)

  M.job_id = vim.fn.jobstart(command, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if not data then
        return
      end

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
          add_golang_test(M.tests, decoded)
          vim.schedule(function() display.update_tracker_buffer() end)
          goto continue
        end

        if decoded.Action == 'output' then
          if decoded.Test or decoded.Package then
            add_golang_output(M.tests, decoded)
          end
          goto continue
        end

        -- Handle pause, cont, and start actions
        if action_state[decoded.Action] then
          mark_outcome(M.tests, decoded)
          vim.schedule(function() display.update_tracker_buffer() end)
          goto continue
        end

        ::continue::
      end
    end,
    on_exit = function()
      vim.schedule(function() display.update_tracker_buffer() end)
    end,
  })
end

vim.api.nvim_create_user_command('GoTestAll', function()
  local command = { 'go', 'test', './...', '-json', '-v' }
  M.run_test_all(command)
end, {})

return M
