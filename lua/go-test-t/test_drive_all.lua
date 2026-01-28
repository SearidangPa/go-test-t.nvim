local M = {}

if vim.fn.has("win32") == 1 then
    M.run = function() end
    return M
end

function M.run(opts)
    local env_mode = opts.args ~= "" and opts.args or "dev"

    if env_mode ~= "dev" and env_mode ~= "staging" then
        vim.notify(
            "Error: Invalid environment. Use 'dev' or 'staging'",
            vim.log.levels.ERROR
        )
        return
    end

    local report_file = vim.fn.expand("$HOME") .. "/Downloads/tests_report.md"

    local initial_content = {
        "Environment: " .. env_mode,
        "",
        "**Discovering tests...**",
        "",
    }

    vim.fn.writefile(initial_content, report_file)

    vim.cmd("edit " .. vim.fn.fnameescape(report_file))
    local bufnr = vim.api.nvim_get_current_buf()

    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].filetype = "markdown"

    local state = {
        test_queue = {},
        running_jobs = {},
        results = {},
        total_tests = 0,
        completed_tests = 0,
        passed_tests = 0,
        failed_tests = 0,
        max_concurrent = 4,
        bufnr = bufnr,
        report_file = report_file,
        test_names = {},
        tests_discovered = false,
        shutting_down = false,
    }

    local function build_test_cmd(test_name)
        local template = table.concat({
            "cd %s && MODE=%s UKS=others go test ",
            "-exec 'env DYLD_LIBRARY_PATH=%s/bin' ",
            "./integration_tests/ -v -run '^%s$' -timeout 30s 2>&1",
        })

        local cwd = vim.fn.getcwd()
        local mode = env_mode

        return string.format(template, cwd, mode, cwd, test_name)
    end

    local function update_file_display()
        if state.shutting_down then
            return
        end

        local lines = {
            "Environment: " .. env_mode,
            "",
        }

        if not state.tests_discovered then
            table.insert(lines, "**Discovering tests...**")
        elseif state.total_tests == 0 then
            table.insert(lines, "⚠️ **No tests found**")
        else
            table.insert(
                lines,
                "## Progress: "
                    .. state.completed_tests
                    .. "/"
                    .. state.total_tests
            )

            if #state.running_jobs > 0 then
                table.insert(lines, "")
                table.insert(lines, "### Currently Running:")
                table.insert(lines, "")
                for _, job in ipairs(state.running_jobs) do
                    table.insert(lines, "  🔥 " .. job.name)
                end
            end

            if #state.test_queue > 0 then
                table.insert(lines, "")
                table.insert(
                    lines,
                    "### Queued: " .. #state.test_queue .. " tests remaining"
                )
                table.insert(lines, "")
            end

            table.insert(lines, "")
            table.insert(lines, "## Results")
            table.insert(lines, "")

            for _, test_name in ipairs(state.test_names) do
                local result = state.results[test_name]
                if result then
                    if result.passed then
                        table.insert(lines, test_name .. ": **PASS** ✅")
                    else
                        table.insert(lines, test_name .. ": **FAILED** ❌")
                        table.insert(lines, "```")

                        local output_lines =
                            vim.split(result.output, "\n", { trimempty = true })
                        local start_idx = math.max(1, #output_lines - 9)
                        for i = start_idx, #output_lines do
                            table.insert(lines, output_lines[i])
                        end

                        table.insert(lines, "```")
                    end
                end
            end

            table.insert(lines, "## Summary")
            table.insert(lines, "- Total Tests: " .. state.total_tests)
            table.insert(lines, "- Completed: " .. state.completed_tests)
            table.insert(lines, "- Passed: " .. state.passed_tests)
            table.insert(lines, "- Failed: " .. state.failed_tests)

            if state.completed_tests == state.total_tests then
                table.insert(lines, "")
                table.insert(lines, "✅ **All tests complete!**")
            end
        end

        vim.fn.writefile(lines, state.report_file)

        if
            not state.shutting_down and vim.api.nvim_buf_is_valid(state.bufnr)
        then
            vim.schedule(function()
                if
                    state.shutting_down
                    or not vim.api.nvim_buf_is_valid(state.bufnr)
                then
                    return
                end

                local current_buf = vim.api.nvim_get_current_buf()
                vim.bo[state.bufnr].modifiable = true
                vim.api.nvim_buf_call(state.bufnr, function()
                    vim.cmd("edit!")
                end)
                vim.bo[state.bufnr].modifiable = false

                if
                    current_buf ~= state.bufnr
                    and vim.api.nvim_buf_is_valid(current_buf)
                then
                    vim.api.nvim_set_current_buf(current_buf)
                end
            end)
        end
    end

    local function start_next_test()
        if state.shutting_down then
            return
        end

        if
            #state.test_queue == 0
            or #state.running_jobs >= state.max_concurrent
        then
            return
        end

        local test_name = table.remove(state.test_queue, 1)
        if not test_name then
            return
        end

        local test_cmd = build_test_cmd(test_name)
        local output_buffer = {}

        local job_id = vim.fn.jobstart({ "sh", "-c", test_cmd }, {
            stdout_buffered = false,
            stderr_buffered = false,
            on_stdout = function(_, data)
                if data then
                    for _, line in ipairs(data) do
                        if line ~= "" then
                            table.insert(output_buffer, line)
                        end
                    end
                end
            end,
            on_stderr = function(_, data)
                if data then
                    for _, line in ipairs(data) do
                        if line ~= "" then
                            table.insert(output_buffer, line)
                        end
                    end
                end
            end,
            on_exit = function(job_id, exit_code)
                if state.shutting_down then
                    return
                end

                for i = #state.running_jobs, 1, -1 do
                    if state.running_jobs[i].id == job_id then
                        table.remove(state.running_jobs, i)
                        break
                    end
                end

                local output = table.concat(output_buffer, "\n")
                local passed = exit_code == 0

                state.results[test_name] = {
                    passed = passed,
                    output = output,
                }

                state.completed_tests = state.completed_tests + 1

                if passed then
                    state.passed_tests = state.passed_tests + 1
                else
                    state.failed_tests = state.failed_tests + 1
                end

                update_file_display()

                if state.completed_tests == state.total_tests then
                    local summary = string.format(
                        "Test execution complete! Total: %d | Passed: %d | Failed: %d",
                        state.total_tests,
                        state.passed_tests,
                        state.failed_tests
                    )
                    vim.notify(
                        summary,
                        state.failed_tests > 0 and vim.log.levels.WARN
                            or vim.log.levels.INFO
                    )
                    -- notify where the report file is
                    vim.notify(
                        string.format(
                            "Test report written to: %s",
                            state.report_file
                        ),
                        vim.log.levels.INFO
                    )
                else
                    vim.schedule(function()
                        start_next_test()
                    end)
                end
            end,
        })

        if job_id > 0 then
            table.insert(state.running_jobs, { id = job_id, name = test_name })
            update_file_display()
        else
            vim.notify(
                "Failed to start job for: " .. test_name,
                vim.log.levels.ERROR
            )
        end
    end

    local test_list_cmd = "cd "
        .. vim.fn.getcwd()
        .. " && go test ./integration_tests/ -list 'Test_' 2>/dev/null"

    local test_output = {}

    vim.fn.jobstart({ "sh", "-c", test_list_cmd }, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" and line:match("^Test_") then
                        table.insert(test_output, line)
                    end
                end
            end
        end,
        on_exit = function(_, exit_code)
            if state.shutting_down then
                return
            end

            state.tests_discovered = true

            if exit_code ~= 0 or #test_output == 0 then
                vim.notify(
                    "No tests found starting with Test_ in ./integration_tests/",
                    vim.log.levels.WARN
                )
                state.total_tests = 0
                update_file_display()
                return
            end

            state.test_names = test_output
            state.test_queue = vim.deepcopy(test_output)
            state.total_tests = #test_output

            update_file_display()

            for _ = 1, math.min(state.max_concurrent, #test_output) do
                start_next_test()
            end
        end,
    })

    local function cleanup_jobs()
        state.shutting_down = true
        for _, job in ipairs(state.running_jobs) do
            pcall(vim.fn.jobstop, job.id)
        end
        state.running_jobs = {}
    end

    vim.api.nvim_create_autocmd("BufDelete", {
        buffer = bufnr,
        once = true,
        callback = cleanup_jobs,
    })

    local cleanup_group = vim.api.nvim_create_augroup(
        "TestDriveCleanup_" .. bufnr,
        { clear = true }
    )
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = cleanup_group,
        callback = function()
            cleanup_jobs()
            vim.wait(100, function()
                return #state.running_jobs == 0
            end, 10)
        end,
    })
end

return M
