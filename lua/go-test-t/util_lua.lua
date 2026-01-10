local M = {}

---@return string? , number?
function M.get_enclosing_test()
    local node = vim.treesitter.get_node()

    -- Traverse up to find the function call
    while node do
        if node:type() == "function_call" then
            local func_name_node = node:field("name")[1]
            if func_name_node then
                local func_name =
                    vim.treesitter.get_node_text(func_name_node, 0)
                if func_name == "it" then
                    -- Found the 'it' block
                    -- Now extract the test description from the first argument
                    local args_node = node:field("arguments")[1]
                    if args_node then
                        -- The arguments node has children: "(", arg1, ",", arg2, ")"
                        -- Or we can just iterate children and find the string

                        -- Let's use the query to be more robust as per user suggestion
                        -- But since we already have the node, we can just inspect children

                        for i = 0, args_node:named_child_count() - 1 do
                            local child = args_node:named_child(i)
                            if child:type() == "string" then
                                -- Better to try to get content field, or iterate children
                                local test_name_node
                                local content_nodes = child:field("content")
                                if #content_nodes > 0 then
                                    test_name_node = content_nodes[1]
                                else
                                    -- fallback if field not found, maybe just get text of string and strip quotes?
                                    -- But let's assume the user query structure is correct for the grammar.
                                    -- User query: (string content: (string_content))
                                    -- So it should have a content field.
                                    -- However, if I can't resolve field, I'll try named_child(0) if it's the only one.
                                    test_name_node = child:named_child(0)
                                end

                                if test_name_node then
                                    local test_name =
                                        vim.treesitter.get_node_text(
                                            test_name_node,
                                            0
                                        )

                                    -- Sanitize the test name:
                                    -- 1. Replace newlines with spaces
                                    -- 2. Collapse multiple spaces
                                    -- 3. Trim whitespace
                                    test_name = test_name
                                        :gsub("\n", " ")
                                        :gsub("%s+", " ")
                                        :match("^%s*(.-)%s*$")

                                    local startLine, _, _ = node:start()
                                    return test_name, startLine + 1
                                end
                            end
                        end
                    end
                end
            end
        end
        node = node:parent()
    end

    return nil, nil
end

return M
