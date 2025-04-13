local fidget = require 'fidget'
local terminal_multiplexer = require 'terminal_test.terminal_multiplexer'
local util_quickfix = require 'async_job.util_quickfix'
local display = require 'go-test-t-display'

---@class terminalTest
local terminal_test_M = {}
terminal_test_M.__index = terminal_test_M

function terminal_test_M.new(opts)
  opts = opts or {}

  local self = setmetatable({}, terminal_test_M)
  self.terminals = terminal_multiplexer.new()
  self.tests_info = {}
  self.displayer = display.new {
    display_title = 'Terminal Test Results',
    toggle_term_func = function(test_name) self.terminals:toggle_float_terminal(test_name) end,
    rerun_in_term_func = function(test_name) self:retest_in_terminal_by_name(test_name) end,
  }
  self.ns_id = opts.ns_id or vim.api.nvim_create_namespace 'Terminal Test'
  self.test_command_format = opts.test_command_format or 'go test ./... -v -run %s\r'
  self:_setup_user_commands()
  return self
end

---@param test_info terminal.testInfo
function terminal_test_M:test_in_terminal(test_info, cb_update_tracker)
  self:_validate_test_info(test_info)
  self.terminals:toggle_float_terminal(test_info.name)
  local float_term_state = self.terminals:toggle_float_terminal(test_info.name)
  vim.api.nvim_chan_send(float_term_state.chan, test_info.test_command .. '\n')

  local self_ref = self
  vim.schedule(function()
    vim.api.nvim_buf_attach(float_term_state.buf, false, {
      on_lines = function(_, buf, _, first_line, last_line)
        return self_ref:_process_buffer_lines(buf, first_line, last_line, test_info, float_term_state, cb_update_tracker)
      end,
    })
  end)
end

function terminal_test_M:toggle_test_in_term(test_name)
  assert(test_name, 'No test name found')
  local test_info = self.tests_info[test_name]
  if not test_info then
    self:retest_in_terminal_by_name(test_name)
  end
  self.terminals:toggle_float_terminal(test_name)
end

function terminal_test_M:retest_in_terminal_by_name(test_name)
  assert(test_name, 'No test name found')
  local test_command = string.format(self.test_command_format, test_name)

  local self_ref = self
  require('util_lsp').action_from_test_name(test_name, function(lsp_param)
    local test_info = {
      test_line = lsp_param.test_line,
      filepath = lsp_param.filepath,
      test_bufnr = lsp_param.test_bufnr,
      name = test_name,
      test_command = test_command,
      status = 'start',
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

function terminal_test_M:test_buf_in_terminals()
  local source_bufnr = vim.api.nvim_get_current_buf()
  local util_find_test = require 'util_find_test'
  local all_tests_in_buf = util_find_test.find_all_tests_in_buf(source_bufnr)
  self.displayer:create_window_and_buf()

  for test_name, test_line in pairs(all_tests_in_buf) do
    self.terminals:delete_terminal(test_name)
    local test_command = string.format(self.test_command_format, test_name)

    local test_info = {
      name = test_name,
      test_line = test_line,
      test_bufnr = source_bufnr,
      test_command = test_command,
      status = 'start',
      filepath = vim.fn.expand '%:p',
      set_ext_mark = false,
      fidget_handle = fidget.progress.handle.create {
        lsp_client = {
          name = test_name,
        },
      },
    }
    self.tests_info[test_name] = test_info
    self:test_in_terminal(test_info)
    vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
  end
end

function terminal_test_M:test_nearest_in_terminal()
  local util_find_test = require 'util_find_test'
  local test_name, test_line = util_find_test.get_enclosing_test()
  assert(test_name, 'Not inside a test function')
  assert(test_line, 'No test line found')

  self.terminals:delete_terminal(test_name)
  self:test_in_terminal {
    name = test_name,
    test_line = test_line,
    test_bufnr = vim.api.nvim_get_current_buf(),
    test_command = string.format(self.test_command_format, test_name),
    status = 'start',
    filepath = vim.fn.expand '%:p',
    set_ext_mark = false,
    fidget_handle = fidget.progress.handle.create {
      lsp_client = {
        name = test_name,
      },
    },
  }
end

function terminal_test_M:view_enclosing_test_terminal()
  local util_find_test = require 'util_find_test'
  local test_name, _ = util_find_test.get_enclosing_test()
  assert(test_name, 'No test found')
  self:toggle_test_in_term(test_name)
end

function terminal_test_M:view_last_test_terminal()
  local test_name = self.terminals.last_terminal_name
  if not test_name then
    vim.notify('No last test terminal found', vim.log.levels.WARN)
    return
  end
  self.terminals:toggle_float_terminal(test_name)
end

--- === Private ===

--- === Process Buffer Lines ===
function terminal_test_M:_process_buffer_lines(buf, first_line, last_line, test_info, float_term_state, cb_update_tracker)
  local lines = vim.api.nvim_buf_get_lines(buf, first_line, last_line, false)
  local current_time = os.date '%H:%M:%S'

  for _, line in ipairs(lines) do
    local detach = self:_process_one_line(line, test_info, float_term_state, current_time, cb_update_tracker)
    if detach then
      test_info.fidget_handle:finish()
      return true
    end
  end
end

function terminal_test_M:_handle_test_passed(test_info, float_term_state, current_time, cb_update_tracker)
  if not test_info.set_ext_mark then
    vim.api.nvim_buf_set_extmark(test_info.test_bufnr, self.ns_id, test_info.test_line - 1, 0, {
      virt_text = { { string.format('✅ %s', current_time) } },
      virt_text_pos = 'eol',
    })
    test_info.set_ext_mark = true
  end
  test_info.status = 'pass'
  float_term_state.status = 'pass'
  self.tests_info[test_info.name] = test_info
  vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
  if cb_update_tracker then
    cb_update_tracker(test_info)
  end
end

function terminal_test_M:_handle_test_failed(test_info, float_term_state, current_time, cb_update_tracker)
  if not test_info.set_ext_mark then
    vim.api.nvim_buf_set_extmark(test_info.test_bufnr, self.ns_id, test_info.test_line - 1, 0, {
      virt_text = { { string.format('❌ %s', current_time) } },
      virt_text_pos = 'eol',
    })
    test_info.set_ext_mark = true
  end
  test_info.status = 'fail'
  float_term_state.status = 'fail'
  self.tests_info[test_info.name] = test_info
  util_quickfix.add_fail_test(test_info)
  vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
  if cb_update_tracker then
    cb_update_tracker(test_info)
  end
end

function terminal_test_M:_handle_error_trace(line, test_info, cb_update_tracker)
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
    vim.schedule(function() self.displayer:update_buffer(self.tests_info) end)
    util_quickfix.add_fail_test(test_info)
    if cb_update_tracker then
      cb_update_tracker(test_info)
    end
  end
end

function terminal_test_M:_process_one_line(line, test_info, float_term_state, current_time, cb_update_tracker)
  self:_handle_error_trace(line, test_info, cb_update_tracker)

  if string.match(line, '--- FAIL') then
    fidget.notify(string.format('%s fail', test_info.name), vim.log.levels.ERROR)
    self:_handle_test_failed(test_info, float_term_state, current_time, cb_update_tracker)
    return true
  elseif string.match(line, 'FAIL') then
    fidget.notify(string.format('%s fail', test_info.name), vim.log.levels.ERROR)
    self:_handle_test_failed(test_info, float_term_state, current_time, cb_update_tracker)
    return true
  elseif string.match(line, '--- PASS') then
    self:_handle_test_passed(test_info, float_term_state, current_time, cb_update_tracker)
    return true
  end
end

--- === Validate Test Info ===

function terminal_test_M:_validate_test_info(test_info)
  assert(test_info.name, 'No test found')
  assert(test_info.test_bufnr, 'No test buffer found')
  assert(test_info.test_line, 'No test line found')
  assert(test_info.test_command, 'No test command found')
  assert(vim.api.nvim_buf_is_valid(test_info.test_bufnr), 'Invalid buffer')
end

--- === Setup user Commands ===
function terminal_test_M:_setup_user_commands()
  local self_ref = self
  vim.api.nvim_create_user_command('TermTestSearch', function() self_ref.terminals:search_terminal() end, {})
  vim.api.nvim_create_user_command('TermTestLast', function() self_ref:view_last_test_terminal() end, {})
  vim.api.nvim_create_user_command('TermTestToggleDisplay', function() self_ref.displayer:toggle_display() end, {})
  vim.api.nvim_create_user_command('QuickfixLoadQuackTest', function() util_quickfix.load_non_passing_tests_to_quickfix(self_ref.tests_info) end, {})
end

return terminal_test_M
