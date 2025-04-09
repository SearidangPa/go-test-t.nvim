local M = {}
M.display_win = -1
M.display_buf = -1
M.original_test_win = -1
M.original_test_buf = -1
M.ns = -1

local make_notify = require('mini.notify').make_notify {}

---@param tests_info gotest.Test[]
local function parse_test_state_to_lines(tests_info)
  local lines = {}
  local packages = {}
  local package_tests = {}

  -- Group tests by package
  for _, test in pairs(tests_info) do
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

---@param tests gotest.Test[]
M.update_tracker_buffer = function(tests)
  local lines = parse_test_state_to_lines(tests)

  -- Only update if the buffer is valid
  if vim.api.nvim_buf_is_valid(M.display_buf) then
    vim.api.nvim_buf_set_lines(M.display_buf, 0, -1, false, lines)

    -- Apply highlights
    local ns = M.ns
    vim.api.nvim_buf_clear_namespace(M.display_buf, ns, 0, -1)

    -- Highlight package names
    for i, line in ipairs(lines) do
      if line:match '^📦' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.display_buf, ns, 'Directory', i - 1, 0, -1)
      elseif line:match '^  ✅' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.display_buf, ns, 'DiagnosticOk', i - 1, 0, -1)
      elseif line:match '^  ❌' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.display_buf, ns, 'DiagnosticError', i - 1, 0, -1)
      elseif line:match '^  ⏸️' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.display_buf, ns, 'DiagnosticWarn', i - 1, 0, -1)
      elseif line:match '^  ▶️' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.display_buf, ns, 'DiagnosticInfo', i - 1, 0, -1)
      elseif line:match '^    ↳' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(M.display_buf, ns, 'Comment', i - 1, 0, -1)
      end
    end
  end
end

M.jump_to_test_location = function()
  -- Get current line
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local line = vim.api.nvim_buf_get_lines(M.display_buf, line_nr - 1, line_nr, false)[1]

  local file, line_num = line:match '->%s+([%w_%-]+%.go):(%d+)'

  if file and line_num then
    -- Switch to original window
    vim.api.nvim_set_current_win(M.original_test_win)

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

---@param tests gotest.Test[] | nil
M.setup_display_buffer = function(tests)
  -- Create the namespace for highlights if it doesn't exist
  if M.ns == -1 then
    M.ns = vim.api.nvim_create_namespace 'go_test_tracker'
  end

  -- Save current window and buffer
  M.original_test_win = vim.api.nvim_get_current_win()
  M.original_test_buf = vim.api.nvim_get_current_buf()

  -- Create a new buffer if needed
  if not vim.api.nvim_buf_is_valid(M.display_buf) then
    M.display_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(M.display_buf, 'Go Test All')
    vim.bo[M.display_buf].bufhidden = 'hide'
    vim.bo[M.display_buf].buftype = 'nofile'
    vim.bo[M.display_buf].swapfile = false
  end

  -- Create a new window if needed
  if not vim.api.nvim_win_is_valid(M.display_win) then
    vim.cmd 'vsplit'
    M.display_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.display_win, M.display_buf)
    vim.api.nvim_win_set_width(M.display_win, math.floor(vim.o.columns / 3))
    vim.wo[M.display_win].number = false
    vim.wo[M.display_win].relativenumber = false
    vim.wo[M.display_win].wrap = false
    vim.wo[M.display_win].signcolumn = 'no'
    vim.wo[M.display_win].foldenable = false
  end

  -- Update the buffer with initial content
  if tests then
    M.update_tracker_buffer(tests)
  end

  -- Return to original window
  vim.api.nvim_set_current_win(M.original_test_win)

  -- Set up keymaps in the tracker buffer
  local setup_keymaps = function()
    -- Close tracker with q
    vim.keymap.set('n', 'q', function() M.close_display() end, { buffer = M.display_buf, noremap = true, silent = true })

    -- Jump to test file location with <CR>
    vim.keymap.set('n', '<CR>', function() M.jump_to_test_location() end, { buffer = M.display_buf, noremap = true, silent = true })
  end

  setup_keymaps()
end

M.close_display = function()
  if vim.api.nvim_win_is_valid(M.display_win) then
    vim.api.nvim_win_close(M.display_win, true)
    M.display_win = -1
  end
end

vim.api.nvim_create_user_command('GoTestDisplayToggle', function()
  if vim.api.nvim_win_is_valid(M.display_win) then
    vim.api.nvim_win_close(M.display_win, true)
    M.display_win = -1
  else
    M.setup_display_buffer()
  end
end, {})

return M
