local fidget = require 'fidget'

---@class termTester
local terminal_test = {}
terminal_test.__index = terminal_test

---@param opts termTest.Options
function terminal_test.new(opts)
  assert(opts, 'No options found')
  assert(opts.pin_test_func, 'No pin test function found')
  assert(opts.display_title, 'No display title found')

  local self = setmetatable({}, terminal_test)
  self.terminals = require('terminal-multiplexer').new {}
  self.tests_info = opts.tests_info or {}
  self.displayer = require('util_go_test_display').new {
    display_title = opts.display_title,
    toggle_term_func = function(test_name) self.terminals:toggle_float_terminal(test_name) end,
    rerun_in_term_func = function(test_name) self:retest_in_terminal_by_name(test_name) end,
  }
  self.ns_id = opts.ns_id or vim.api.nvim_create_namespace 'Terminal Test'
  self.term_test_command_format = opts.term_test_command_format or 'go test ./... -v -run %s\r'
  self.pin_test_func = opts.pin_test_func
  return self
end

function terminal_test:reset()
  self.tests_info = {}
  self.displayer:reset()
end

---@param test_info terminal.testInfo
function terminal_test:test_in_terminal(test_info)
  self:_validate_test_info(test_info)
  self.terminals:toggle_float_terminal(test_info.name)
  local float_term_state = self.terminals:toggle_float_terminal(test_info.name)
  vim.api.nvim_chan_send(float_term_state.chan, test_info.test_command .. '\n')

  local self_ref = self
  vim.schedule(function()
    vim.api.nvim_buf_attach(float_term_state.buf, false, {
      on_lines = function(_, buf, _, first_line, last_line) return self_ref:_process_buffer_lines(buf, first_line, last_line, test_info) end,
    })
  end)
end

function terminal_test:toggle_test_in_term(test_name)
  assert(test_name, 'No test name found')
  local test_info = self.tests_info[test_name]
  if not test_info then
    self:retest_in_terminal_by_name(test_name)
  end
  self.terminals:toggle_float_terminal(test_name)
end

function terminal_test:retest_in_terminal_by_name(test_name)
  assert(test_name, 'No test name found')
  local test_command = string.format(self.term_test_command_format, test_name)

  local self_ref = self
  require('util_lsp').action_from_test_name(test_name, function(lsp_param)
    local test_info = {
      test_line = lsp_param.test_line,
      filepath = lsp_param.filepath,
      test_bufnr = lsp_param.test_bufnr,
      name = test_name,
      test_command = test_command,
      status = 'fired',
      set_ext_mark = false,
      fidget_handle = fidget.progress.handle.create {
        lsp_client = {
          name = test_name,
        },
      },
    }
    self_ref:test_in_terminal(test_info)
  end)
end

function terminal_test:test_buf_in_terminals()
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'util_find_test'
  local all_tests_in_buf = util_find_test.find_all_tests_in_buf(source_bufnr)
  self.displayer:create_window_and_buf()

  for test_name, test_line in pairs(all_tests_in_buf) do
    self.terminals:delete_terminal(test_name)
    local test_command = string.format(self.term_test_command_format, test_name)

    ---@type terminal.testInfo
    local test_info = {
      name = test_name,
      test_line = test_line,
      test_bufnr = source_bufnr,
      test_command = test_command,
      status = 'fired',
      filepath = vim.fn.expand '%:p',
      set_ext_mark = false,
    }
    self.tests_info[test_name] = test_info
    self:_auto_update_test_line(test_info)
    self:test_in_terminal(test_info)
    vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
  end
end

function terminal_test:test_nearest_in_terminal()
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'Not inside a test function')
  assert(test_line, 'No test line found')
  self.terminals:delete_terminal(test_name)

  ---@type terminal.testInfo
  local test_info = {
    name = test_name,
    test_line = test_line,
    test_bufnr = vim.api.nvim_get_current_buf(),
    test_command = string.format(self.term_test_command_format, test_name),
    status = 'fired',
    filepath = vim.fn.expand '%:p',
    set_ext_mark = false,
    fidget_handle = fidget.progress.handle.create {
      lsp_client = {
        name = test_name,
      },
    },
  }

  vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
  self:test_in_terminal(test_info)
  self:_auto_update_test_line(test_info)
  return test_info
end

function terminal_test:view_enclosing_test_terminal()
  local util_find_test = require 'util_find_test'
  local test_name, _ = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  self:toggle_test_in_term(test_name)
end

function terminal_test:view_last_test_terminal()
  local test_name = self.terminals.last_terminal_name
  if not test_name then
    vim.notify('No last test terminal found', vim.log.levels.WARN)
    return
  end
  self.terminals:toggle_float_terminal(test_name)
end

--- === Private ===

---@param test_info terminal.testInfo
function terminal_test:_auto_update_test_line(test_info)
  local augroup = vim.api.nvim_create_augroup('TestLineTracker_' .. test_info.name, { clear = true })
  local util_lsp = require 'util_lsp'

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup,
    buffer = test_info.test_bufnr,
    callback = function()
      util_lsp.action_from_test_name(test_info.name, function(new_info)
        if new_info.test_line ~= test_info.test_line then
          test_info.test_line = new_info.test_line
          test_info.test_bufnr = new_info.test_bufnr
          test_info.filepath = new_info.filepath
        end
      end)
    end,
  })

  return augroup
end

--- === Process Buffer Lines ===

---@param buf number
---@param first_line number
---@param last_line number
---@param test_info terminal.testInfo
function terminal_test:_process_buffer_lines(buf, first_line, last_line, test_info)
  local lines = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)
  local current_time = os.date '%H:%M:%S'

  for _, line in ipairs(lines) do
    local detach = self:_process_one_line(line, test_info, current_time)
    if detach then
      if test_info.fidget_handle then
        test_info.fidget_handle:finish()
      end
      return true
    end
  end
end

---@param test_info terminal.testInfo
---@param current_time string
function terminal_test:_handle_test_passed(test_info, current_time)
  if not test_info.set_ext_mark then
    vim.api.nvim_buf_set_extmark(test_info.test_bufnr, self.ns_id, test_info.test_line - 1, 0, {
      virt_text = { { string.format('✅ %s', current_time) } },
      virt_text_pos = 'eol',
    })
    test_info.set_ext_mark = true
  end
  test_info.status = 'pass'
  self.tests_info[test_info.name] = test_info
  vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
end

function terminal_test:_handle_test_failed(test_info, current_time)
  if not test_info.set_ext_mark then
    vim.api.nvim_buf_set_extmark(test_info.test_bufnr, self.ns_id, test_info.test_line - 1, 0, {
      virt_text = { { string.format('❌ %s', current_time) } },
      virt_text_pos = 'eol',
    })
    test_info.set_ext_mark = true
  end
  test_info.status = 'fail'
  self.tests_info[test_info.name] = test_info
  self.pin_test_func(test_info)
  require('util_go_test_quickfix').add_fail_test(test_info)
  vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
end

---@param line string
---@param test_info terminal.testInfo
function terminal_test:_handle_error_trace(line, test_info)
  local file, line_num
  if vim.fn.has 'win32' == 1 then
    file, line_num = string.match(line, 'Error Trace:%s+([%w%p]+):(%d+)')
  else
    file, line_num = string.match(line, 'Error Trace:%s+([^:]+):(%d+)')
  end

  if file and line_num then
    local error_bufnr = vim.fn.bufnr(file)
    if error_bufnr then
      vim.fn.sign_define('GoTestError', { text = '❌', texthl = 'DiagnosticError' })
      vim.fn.sign_place(0, 'GoTestErrorGroup', 'GoTestError', error_bufnr, { lnum = line_num })
    end
    test_info.status = 'fail'
    test_info.fail_at_line = line_num
    self.tests_info[test_info.name] = test_info
    self.pin_test_func(test_info)
    vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
    require('util_go_test_quickfix').add_fail_test(test_info)
  end
end

---@param line string
---@param test_info terminal.testInfo
---@param current_time string
function terminal_test:_process_one_line(line, test_info, current_time)
  self:_handle_error_trace(line, test_info)

  if string.match(line, '--- FAIL') then
    if test_info.fidget_handle then
      local make_notify = require('mini.notify').make_notify {}
      make_notify(string.format('%s fail', test_info.name), vim.log.levels.ERROR)
    end
    self:_handle_test_failed(test_info, current_time)
    return true
  elseif string.match(line, '--- PASS') then
    if test_info.fidget_handle then
      local make_notify = require('mini.notify').make_notify {}
      make_notify(string.format('%s pass', test_info.name), vim.log.levels.INFO)
    end
    self:_handle_test_passed(test_info, current_time)
    return true
  end
end

--- === Validate Test Info ===

---@param test_info terminal.testInfo
function terminal_test:_validate_test_info(test_info)
  assert(test_info.name, 'No test found')
  assert(test_info.test_bufnr, 'No test buffer found')
  assert(test_info.test_line, 'No test line found')
  assert(test_info.test_command, 'No test command found')
  assert(vim.api.nvim_buf_is_valid(test_info.test_bufnr), 'Invalid buffer')
end

return terminal_test
