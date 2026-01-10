local M = {}

function M.get_intermediate_path(filepath)
    local cwd = vim.fn.getcwd()
    filepath = filepath or vim.fn.expand("%:p")
    local path_sep = package.config:sub(1, 1)
    cwd = cwd:gsub("/", path_sep):gsub("\\", path_sep)
    filepath = filepath:gsub("/", path_sep):gsub("\\", path_sep)

    if cwd:sub(-1) ~= path_sep then
        cwd = cwd .. path_sep
    end

    -- Check if the filepath starts with the current working directory
    if filepath:sub(1, #cwd) ~= cwd then
        vim.notify(
            "The file path does not start with the current working directory.",
            vim.log.levels.WARN
        )
        return nil
    end

    local relative_path = filepath:sub(#cwd + 1)
    local segments = {}

    -- Extracts just the directory part of the relative path
    local path_only = vim.fn.fnamemodify(relative_path, ":h")

    -- If there's no directory structure, returns "./"
    if path_only == "." then
        return "." .. path_sep
    end

    -- [^' .. path_sep .. ']+ means "match one or more characters that are NOT the path separator character."
    -- For example, if path_only is "foo/bar/baz" on a Unix system:
    -- First iteration: segment becomes "foo"
    -- Second iteration: segment becomes "bar"
    -- Third iteration: segment becomes "baz"
    for segment in path_only:gmatch("[^" .. path_sep .. "]+") do
        table.insert(segments, segment)
    end

    local result = "." .. path_sep
    for i, segment in ipairs(segments) do
        result = result .. segment
        if i < #segments then
            result = result .. path_sep
        end
    end

    -- Always add the trailing separator to indicate it's a directory
    if result:sub(-1) ~= path_sep then
        result = result .. path_sep
    end

    return result
end

return M
