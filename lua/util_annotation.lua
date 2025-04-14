---@class GoTestT
---@field tests_info table<string, terminal.testInfo>
---@field job_id number
---@field term_test_command_format string
---@field test_command_format_json string
---@field test_command string
---@field terminal_name string
---@field term_tester terminalTest
---@field user_command_prefix string
---@field ns_id number
---@field set_up fun(self: GoTestT, user_command_prefix: string)
---@field test_all? fun(command: string[])
---@field toggle_display? fun(self: GoTestT)
---@field load_quack_tests? fun(self: GoTestT)
---@field _clean_up_prev_job? fun(self: GoTestT)
---@field _add_golang_test? fun(self: GoTestT, entry: table)
---@field _filter_golang_output? fun(self: GoTestT, entry: table)
---@field _mark_outcome? fun(self: GoTestT, entry: table)
---@field _setup_commands? fun(self: GoTestT)
---
---@class GoTestT.Options
---@field term_test_command_format string
---@field test_command_format_json string
---@field test_command string
---@field terminal_name? string
---@field display_title? string
---@field user_command_prefix? string

---@class terminalTest
---@field terminals TerminalMultiplexer
---@field tests_info table<string, terminal.testInfo>
---@field term_test_displayer? GoTestDisplay
---@field ns_id number
---@field term_test_command_format string

---@class terminal.testInfo
---@field name string
---@field status string
---@field fail_at_line? number
---@field has_details? boolean
---@field test_bufnr number
---@field test_line number
---@field test_command string
---@field filepath string
---@field set_ext_mark boolean
---@field fidget_handle ProgressHandle

---@class TestPinner
---@field pin_list terminal.testInfo[]
---
---@class GoTestDisplay
---@field display_title string
---@field display_win_id number
---@field display_bufnr number
---@field original_test_win number
---@field original_test_buf number
---@field ns_id number
---@field tests_info  terminal.testInfo[]
---@field _close_display fun(self: GoTestDisplay)
---@field toggle_term_func fun(test_name: string)
---@field rerun_in_term_func fun(test_name: string)
