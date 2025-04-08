local M = {}
require 'config.util_find_func'
local make_notify = require('mini.notify').make_notify {}

---@class gotest.State
---@field tracker_win number
---@field tracker_buf number
---@field original_win number
---@field original_buf number
---@field tests table<string, gotest.TestInfo>
---@field job_id number
---@field ns number
---@field last_update number
M.tracker_state = {
  tracker_win = -1,
  tracker_buf = -1,
  original_win = -1,
  original_buf = -1,
  tests = {},
  job_id = -1,
  ns = -1,
}

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

local add_golang_output = function(test_state, entry)
  assert(test_state.tests, vim.inspect(test_state))
  local key = make_key(entry)
  local test = test_state.tests[key]

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

local mark_outcome = function(test_state, entry)
  local key = make_key(entry)
  local test = test_state.tests[key]

  if not test then
    return
  end
  -- Explicitly set the status based on the Action
  test.status = entry.Action
end

---@return string[]
local function parse_test_state_to_lines()
  local lines = {}
  local packages = {}
  local package_tests = {}

  -- Group tests by package
  for key, test in pairs(M.tracker_state.tests) do
    if not packages[test.package] then
      packages[test.package] = true
      package_tests[test.package] = {}
    end

    if test.name then
      table.insert(package_tests[test.package], test)
    end
  end

  -- Sort packages
  local sorted_packages = {}
  for pkg, _ in pairs(packages) do
    table.insert(sorted_packages, pkg)
  end
  table.sort(sorted_packages)

  -- Build display lines
  for _, pkg in ipairs(sorted_packages) do
    table.insert(lines, '📦 ' .. pkg)

    local tests = package_tests[pkg]
    -- Sort tests by status priority and then by name
    table.sort(tests, function(a, b)
      -- If status is the same, sort by name
      if a.status == b.status then
        return a.name < b.name
      end

      -- Define priority: running (1), paused (2), cont (3), start (4), fail (5), pass (6)
      local priority = {
        running = 1,
        paused = 2,
        cont = 3,
        start = 4,
        fail = 5,
        pass = 6,
      }

      if not priority[a.status] and priority[b.status] then
        return true
      end
      if priority[a.status] and not priority[b.status] then
        return false
      end

      if not priority[a.status] and not priority[b.status] then
        return a.name < b.name
      end
      return priority[a.status] < priority[b.status]
    end)

    for _, test in ipairs(tests) do
      local status_icon = '🔄'
      if test.status == 'pass' then
        status_icon = '✅'
      elseif test.status == 'fail' then
        status_icon = '❌'
      elseif test.status == 'paused' then
        status_icon = '⏸️'
      elseif test.status == 'cont' then
        status_icon = '▶️'
      elseif test.status == 'start' then
        status_icon = '🏁'
      end

      if test.status == 'fail' and test.file ~= '' then
        table.insert(lines, string.format('  %s %s -> %s:%d', status_icon, test.name, test.file, test.fail_at_line))
      else
        table.insert(lines, string.format('  %s %s', status_icon, test.name))
      end
    end

    table.insert(lines, '')
  end

  return lines
end

local function update_tracker_buffer()
  local lines = parse_test_state_to_lines()

  -- Only update if the buffer is valid
  if vim.api.nvim_buf_is_valid(M.tracker_state.tracker_buf) then
    vim.api.nvim_buf_set_lines(M.tracker_state.tracker_buf, 0, -1, false, lines)

    -- Apply highlights
    local ns = M.tracker_state.ns
    vim.api.nvim_buf_clear_namespace(M.tracker_state.tracker_buf, ns, 0, -1)

    -- Highlight package names
    for i, line in ipairs(lines) do
      if line:match '^📦' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.tracker_state.tracker_buf, ns, 'Directory', i - 1, 0, -1)
      elseif line:match '^  ✅' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.tracker_state.tracker_buf, ns, 'DiagnosticOk', i - 1, 0, -1)
      elseif line:match '^  ❌' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.tracker_state.tracker_buf, ns, 'DiagnosticError', i - 1, 0, -1)
      elseif line:match '^  ⏸️' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.tracker_state.tracker_buf, ns, 'DiagnosticWarn', i - 1, 0, -1)
      elseif line:match '^  ▶️' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.tracker_state.tracker_buf, ns, 'DiagnosticInfo', i - 1, 0, -1)
      elseif line:match '^    ↳' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.tracker_state.tracker_buf, ns, 'Comment', i - 1, 0, -1)
      end
    end
  end
end

local function setup_tracker_buffer()
  -- Create the namespace for highlights if it doesn't exist
  if M.tracker_state.ns == -1 then
    M.tracker_state.ns = vim.api.nvim_create_namespace 'go_test_tracker'
  end

  -- Save current window and buffer
  M.tracker_state.original_win = vim.api.nvim_get_current_win()
  M.tracker_state.original_buf = vim.api.nvim_get_current_buf()

  -- Create a new buffer if needed
  if not vim.api.nvim_buf_is_valid(M.tracker_state.tracker_buf) then
    M.tracker_state.tracker_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(M.tracker_state.tracker_buf, 'GoTestTracker')
    vim.bo[M.tracker_state.tracker_buf].bufhidden = 'hide'
    vim.bo[M.tracker_state.tracker_buf].buftype = 'nofile'
    vim.bo[M.tracker_state.tracker_buf].swapfile = false
  end

  -- Create a new window if needed
  if not vim.api.nvim_win_is_valid(M.tracker_state.tracker_win) then
    vim.cmd 'vsplit'
    M.tracker_state.tracker_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.tracker_state.tracker_win, M.tracker_state.tracker_buf)
    vim.api.nvim_win_set_width(M.tracker_state.tracker_win, math.floor(vim.o.columns / 3))
    vim.wo[M.tracker_state.tracker_win].number = false
    vim.wo[M.tracker_state.tracker_win].relativenumber = false
    vim.wo[M.tracker_state.tracker_win].wrap = false
    vim.wo[M.tracker_state.tracker_win].signcolumn = 'no'
    vim.wo[M.tracker_state.tracker_win].foldenable = false
  end

  -- Update the buffer with initial content
  update_tracker_buffer()

  -- Return to original window
  vim.api.nvim_set_current_win(M.tracker_state.original_win)

  -- Set up keymaps in the tracker buffer
  local setup_keymaps = function()
    -- Close tracker with q
    vim.keymap.set('n', 'q', function() M.close_tracker() end, { buffer = M.tracker_state.tracker_buf, noremap = true, silent = true })

    -- Jump to test file location with <CR>
    vim.keymap.set('n', '<CR>', function() M.jump_to_test_location() end, { buffer = M.tracker_state.tracker_buf, noremap = true, silent = true })
  end

  setup_keymaps()
end

M.close_tracker = function()
  if vim.api.nvim_win_is_valid(M.tracker_state.tracker_win) then
    vim.api.nvim_win_close(M.tracker_state.tracker_win, true)
    M.tracker_state.tracker_win = -1
  end
end

M.jump_to_test_location = function()
  -- Get current line
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local line = vim.api.nvim_buf_get_lines(M.tracker_state.tracker_buf, line_nr - 1, line_nr, false)[1]

  local file, line_num = line:match '->%s+([%w_%-]+%.go):(%d+)'

  if file and line_num then
    -- Switch to original window
    vim.api.nvim_set_current_win(M.tracker_state.original_win)

    -- Find the file in the project
    local cmd = string.format("find . -name '%s' | head -n 1", file)
    local filepath = vim.fn.system(cmd):gsub('\n', '')

    if filepath ~= '' then
      vim.cmd('edit ' .. filepath)
      vim.api.nvim_win_set_cursor(0, { tonumber(line_num), 0 })
      vim.cmd 'normal! zz'
    else
      make_notify('File not found: ' .. file, 'error')
    end
  end
end

M.run_test_all = function(command)
  -- Reset test state
  M.tracker_state.tests = {}

  -- Set up tracker buffer
  setup_tracker_buffer()

  -- Clean up previous job
  M.clean_up_prev_job(M.tracker_state.job_id)

  M.tracker_state.job_id = vim.fn.jobstart(command, {
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
          add_golang_test(M.tracker_state, decoded)
          vim.schedule(function() update_tracker_buffer() end)
          goto continue
        end

        if decoded.Action == 'output' then
          if decoded.Test or decoded.Package then
            add_golang_output(M.tracker_state, decoded)
          end
          goto continue
        end

        -- Handle pause, cont, and start actions
        if action_state[decoded.Action] then
          mark_outcome(M.tracker_state, decoded)
          vim.schedule(function() update_tracker_buffer() end)
          goto continue
        end

        ::continue::
      end
    end,
    on_exit = function()
      vim.schedule(function() update_tracker_buffer() end)
    end,
  })
end

vim.api.nvim_create_user_command('GoTestAll', function()
  local command = { 'go', 'test', './...', '-json', '-v' }
  M.run_test_all(command)
end, {})

vim.api.nvim_create_user_command('GoTestTrackerToggle', function()
  if vim.api.nvim_win_is_valid(M.tracker_state.tracker_win) then
    M.close_tracker()
  else
    setup_tracker_buffer()
  end
end, {})

--- === on demand: load all tests that have not passed into a single quickfix

local function add_direct_file_entries(test, qf_entries)
  assert(test.file, 'File not found for test: ' .. test.name)
  -- Find the file in the project
  local cmd = string.format("find . -name '%s' | head -n 1", test.file)
  local filepath = vim.fn.system(cmd):gsub('\n', '')

  if filepath ~= '' then
    table.insert(qf_entries, {
      filename = filepath,
      lnum = test.fail_at_line,
      text = string.format('%s', test.name),
    })
  end

  return qf_entries
end

-- Helper function to resolve test locations via LSP
local function resolve_test_locations(tests_to_resolve, qf_entries, on_complete)
  local resolved_count = 0
  local total_to_resolve = #tests_to_resolve

  -- If no tests to resolve, call completion callback immediately
  if total_to_resolve == 0 then
    on_complete(qf_entries)
    return
  end

  for _, test in ipairs(tests_to_resolve) do
    vim.lsp.buf_request(0, 'workspace/symbol', { query = test.name }, function(err, res)
      if err or not res or #res == 0 then
        vim.notify('No definition found for test: ' .. test.name, vim.log.levels.WARN)
      else
        local result = res[1] -- Take the first result
        local filename = vim.uri_to_fname(result.location.uri)
        local start = result.location.range.start

        table.insert(qf_entries, {
          filename = filename,
          lnum = start.line + 1,
          col = start.character + 1,
          text = string.format('%s', test.name),
        })
      end

      resolved_count = resolved_count + 1

      -- When all tests are resolved, call the completion callback
      if resolved_count == total_to_resolve then
        on_complete(qf_entries)
      end
    end)
  end
end

local function populate_quickfix_list(qf_entries)
  if #qf_entries > 0 then
    vim.fn.setqflist(qf_entries, 'r')
    vim.cmd 'copen'
    vim.notify('Loaded ' .. #qf_entries .. ' failing tests to quickfix list', vim.log.levels.INFO)
  else
    vim.notify('No failing tests found', vim.log.levels.INFO)
  end
end

M.load_non_passing_tests_to_quickfix = function()
  local qf_entries = {}
  local tests_to_resolve = {}

  for _, test in pairs(M.tracker_state.tests) do
    if test.status == 'pass' then
      goto continue
    end

    if test.fail_at_line ~= 0 then
      qf_entries = add_direct_file_entries(test, qf_entries)
    else
      table.insert(tests_to_resolve, test)
    end
    ::continue::
  end

  resolve_test_locations(tests_to_resolve, qf_entries, populate_quickfix_list)
  M.close_tracker()
  return qf_entries
end

-- Create a command to load non-passing tests to quickfix
vim.api.nvim_create_user_command('GoTestQuickfix', function() M.load_non_passing_tests_to_quickfix() end, {})
return M
