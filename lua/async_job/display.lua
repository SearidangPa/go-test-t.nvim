-- GoTestDisplay class for displaying Go test results
local GoTestDisplay = {}
GoTestDisplay.__index = GoTestDisplay

local make_notify = require('mini.notify').make_notify {}

-- Constructor
function GoTestDisplay.new()
  local self = setmetatable({}, GoTestDisplay)
  self.display_win = -1
  self.display_buf = -1
  self.original_test_win = -1
  self.original_test_buf = -1
  self.ns = vim.api.nvim_create_namespace 'go_test_display'

  return self
end

---@param tests gotest.TestInfo[] | nil
function GoTestDisplay:setup(tests, title)
  -- Save current window and buffer
  self.original_test_win = vim.api.nvim_get_current_win()
  self.original_test_buf = vim.api.nvim_get_current_buf()

  -- Create a new buffer if needed
  if not vim.api.nvim_buf_is_valid(self.display_buf) then
    self.display_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(self.display_buf, title or 'Go Test Results')
    vim.bo[self.display_buf].bufhidden = 'hide'
    vim.bo[self.display_buf].buftype = 'nofile'
    vim.bo[self.display_buf].swapfile = false
  end

  -- Create a new window if needed
  if not vim.api.nvim_win_is_valid(self.display_win) then
    vim.cmd 'vsplit'
    self.display_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.display_win, self.display_buf)
    vim.api.nvim_win_set_width(self.display_win, math.floor(vim.o.columns / 3))
    vim.wo[self.display_win].number = false
    vim.wo[self.display_win].relativenumber = false
    vim.wo[self.display_win].wrap = false
    vim.wo[self.display_win].signcolumn = 'no'
    vim.wo[self.display_win].foldenable = false
  end

  -- Update the buffer with initial content
  if tests then
    self:update_tracker_buffer(tests)
  end

  -- Return to original window
  vim.api.nvim_set_current_win(self.original_test_win)

  -- Set up keymaps in the tracker buffer
  self:setup_keymaps()
end

---@param tests_info gotest.TestInfo[]
function GoTestDisplay:parse_test_state_to_lines(tests_info)
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

---@param tests_info gotest.TestInfo[]
function GoTestDisplay:update_tracker_buffer(tests_info)
  local lines = self:parse_test_state_to_lines(tests_info)

  if vim.api.nvim_buf_is_valid(self.display_buf) then
    vim.api.nvim_buf_set_lines(self.display_buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(self.display_buf, self.ns, 0, -1)

    for i, line in ipairs(lines) do
      if line:match '^📦' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'Directory', i - 1, 0, -1)
      elseif line:match '^  ✅' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'DiagnosticOk', i - 1, 0, -1)
      elseif line:match '^  ❌' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'DiagnosticError', i - 1, 0, -1)
      elseif line:match '^  ⏸️' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'DiagnosticWarn', i - 1, 0, -1)
      elseif line:match '^  ▶️' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'DiagnosticInfo', i - 1, 0, -1)
      elseif line:match '^    ↳' then
        ---@diagnostic disable-next-line: deprecated
        vim.api.nvim_buf_add_highlight(self.display_buf, self.ns, 'Comment', i - 1, 0, -1)
      end
    end
  end
end

function GoTestDisplay:jump_to_test_location()
  -- Get current line
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local line = vim.api.nvim_buf_get_lines(self.display_buf, line_nr - 1, line_nr, false)[1]

  local file, line_num = line:match '->%s+([%w_%-]+%.go):(%d+)'

  if file and line_num then
    -- Switch to original window
    vim.api.nvim_set_current_win(self.original_test_win)

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

function GoTestDisplay:setup_keymaps()
  -- Ensure we operate on the correct instance
  local tracker = self

  -- Close tracker with q
  vim.keymap.set('n', 'q', function() tracker:close_display() end, { buffer = self.display_buf, noremap = true, silent = true })

  -- Jump to test file location with <CR>
  vim.keymap.set('n', '<CR>', function() tracker:jump_to_test_location() end, { buffer = self.display_buf, noremap = true, silent = true })
end

function GoTestDisplay:close_display()
  if vim.api.nvim_win_is_valid(self.display_win) then
    vim.api.nvim_win_close(self.display_win, true)
    self.display_win = -1
  end
end

function GoTestDisplay:toggle_display()
  if vim.api.nvim_win_is_valid(self.display_win) then
    vim.api.nvim_win_close(self.display_win, true)
    self.display_win = -1
  else
    self:setup()
  end
end

-- Create a user command for each instance
function GoTestDisplay:register_command(command_name)
  local tracker = self
  vim.api.nvim_create_user_command(command_name, function() tracker:toggle_display() end, {})
end

-- Return the constructor for the class
return GoTestDisplay
