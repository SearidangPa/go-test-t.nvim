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

---@param tests_info gotest.TestInfo[]
function GoTestDisplay:setup(tests_info)
  self.original_test_win = vim.api.nvim_get_current_win()
  self.original_test_buf = vim.api.nvim_get_current_buf()

  if not vim.api.nvim_buf_is_valid(self.display_buf) then
    self.display_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(self.display_buf, 'Go Test Results')
    vim.bo[self.display_buf].bufhidden = 'hide'
    vim.bo[self.display_buf].buftype = 'nofile'
    vim.bo[self.display_buf].swapfile = false
  end

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

  if tests_info then
    self:update_tracker_buffer(tests_info)
  end
  vim.api.nvim_set_current_win(self.original_test_win)
  self:setup_keymaps()
end

---@param tests_info gotest.TestInfo[]
function GoTestDisplay:parse_test_state_to_lines(tests_info)
  local lines = {}
  local tests = {}

  for _, test in pairs(tests_info) do
    if test.name then
      table.insert(tests, test)
    end
  end

  table.sort(tests, function(a, b)
    if a.status == b.status then
      return a.name < b.name
    end
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
      table.insert(lines, string.format('%s %s -> %s:%d', status_icon, test.name, test.file, test.fail_at_line))
    else
      table.insert(lines, string.format('%s %s', status_icon, test.name))
    end
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
  vim.keymap.set('n', 'q', function() GoTestDisplay:close_display() end, { buffer = self.display_buf, noremap = true, silent = true })
  vim.keymap.set('n', '<CR>', function() GoTestDisplay():jump_to_test_location() end, { buffer = self.display_buf, noremap = true, silent = true })
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
