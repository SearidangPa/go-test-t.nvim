---@class TestsDisplay
---@field display_win number
---@field display_buf number
---@field original_test_win number
---@field original_test_buf number
---@field ns number
---@field tests_info gotest.TestInfo[] | terminal.testInfo[]
---@field close_display fun(self: TestsDisplay)
local Display = {}
Display.__index = Display

-- Constructor
--- @param tests_info gotest.TestInfo[] | terminal.testInfo[]
function Display.new(tests_info)
  local self = setmetatable({}, Display)
  self.display_win = -1
  self.display_buf = -1
  self.original_test_win = -1
  self.original_test_buf = -1
  self.ns = vim.api.nvim_create_namespace 'go_test_display'
  self.tests_info = tests_info
  return self
end

---@param tests_info? gotest.TestInfo[] | terminal.testInfo[]
function Display:setup(tests_info)
  self.original_test_win = vim.api.nvim_get_current_win()
  self.original_test_buf = vim.api.nvim_get_current_buf()

  if not self.display_buf or not vim.api.nvim_buf_is_valid(self.display_buf) then
    self.display_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[self.display_buf].bufhidden = 'hide'
    vim.bo[self.display_buf].buftype = 'nofile'
    vim.bo[self.display_buf].swapfile = false
  end

  if not self.display_win or not vim.api.nvim_win_is_valid(self.display_win) then
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

---@param tests_info gotest.TestInfo[] | terminal.testInfo[]
function Display:parse_test_state_to_lines(tests_info)
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
      status_icon = '🔥'
    elseif test.status == 'start' then
      status_icon = '🏁'
    end

    if test.status == 'fail' and test.file ~= '' then
      local filename = vim.fn.fnamemodify(test.file, ':t')
      table.insert(lines, string.format('%s %s -> %s:%d', status_icon, test.name, filename, test.fail_at_line))
    else
      table.insert(lines, string.format('%s %s', status_icon, test.name))
    end
  end

  return lines
end

---@param tests_info gotest.TestInfo[] | terminal.testInfo[]
function Display:update_tracker_buffer(tests_info)
  local lines = self:parse_test_state_to_lines(tests_info)

  if vim.api.nvim_buf_is_valid(self.display_buf) then
    vim.api.nvim_buf_set_lines(self.display_buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(self.display_buf, self.ns, 0, -1)

    for i, line in ipairs(lines) do
      if line:match '^  ✅' then
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

function Display:jump_to_test_location()
  if not self.display_buf then
    vim.notify('display_buf is nil in jump_to_test_location', vim.log.levels.ERROR)
    return
  end
  if not self.display_win then
    vim.notify('display_win is nil in jump_to_test_location', vim.log.levels.ERROR)
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_nr = cursor[1]
  local line = vim.api.nvim_buf_get_lines(self.display_buf, line_nr - 1, line_nr, false)[1]
  assert(line, 'No line found in display buffer')

  local test_name = line:match '[❌✅]%s+([%w_%-]+)'
  if not test_name then
    vim.notify('No test name found in line: ' .. line, vim.log.levels.ERROR)
    return
  end

  local test_info = self.tests_info[test_name]
  local filepath = test_info.filepath
  vim.api.nvim_set_current_win(self.original_test_win)
  vim.cmd('edit ' .. filepath)

  if test_info.fail_at_line and test_info.fail_at_line ~= 0 then
    assert(test_info.test_line, 'No test line found')
    vim.api.nvim_win_set_cursor(0, { test_info.fail_at_line, 0 })
  elseif test_info.test_line then
    vim.api.nvim_win_set_cursor(0, { test_info.test_line, 0 })
  else
    vim.notify(string.format('No test line found for test: %s', test_name), vim.log.levels.ERROR)
    return
  end
  vim.cmd 'normal! zz'
end

function Display:setup_keymaps()
  local this = self -- Capture the current 'self' reference
  vim.keymap.set('n', 'q', function()
    this:close_display() -- Use the captured reference
  end, { buffer = this.display_buf, noremap = true, silent = true })

  vim.keymap.set('n', '<CR>', function()
    this:jump_to_test_location() -- Use the captured reference
  end, { buffer = this.display_buf, noremap = true, silent = true })
end

function Display:close_display()
  if vim.api.nvim_win_is_valid(self.display_win) then
    vim.api.nvim_win_close(self.display_win, true)
    self.display_win = -1
  end
end

function Display:toggle_display()
  if vim.api.nvim_win_is_valid(self.display_win) then
    vim.api.nvim_win_close(self.display_win, true)
    self.display_win = -1
  else
    self:setup()
  end
end

-- Create a user command for each instance
function Display:register_command(command_name)
  local tracker = self
  vim.api.nvim_create_user_command(command_name, function() tracker:toggle_display() end, {})
end

-- Return the constructor for the class
return Display
