local M = {}

---@return string?
function M.get_intermediate_path(filepath)
  local cwd = vim.fn.getcwd()
  filepath = filepath or vim.fn.expand '%:p'
  local path_sep = package.config:sub(1, 1) -- Gets OS path separator

  -- Normalize paths to use consistent separators
  cwd = cwd:gsub('/', path_sep):gsub('\\', path_sep)
  filepath = filepath:gsub('/', path_sep):gsub('\\', path_sep)

  -- Ensure cwd ends with separator
  if cwd:sub(-1) ~= path_sep then
    cwd = cwd .. path_sep
  end

  -- Check if filepath starts with cwd
  if filepath:sub(1, #cwd) ~= cwd then
    return nil -- File is not in current working directory
  end

  -- Get relative path
  local relative_path = filepath:sub(#cwd + 1)

  -- Find the first directory separator
  local first_dir_end = relative_path:find(path_sep)

  -- Build intermediate path with proper prefix
  local intermediate_path = ''
  if first_dir_end then
    local first_dir = relative_path:sub(1, first_dir_end - 1)
    intermediate_path = '.' .. path_sep .. first_dir
  end

  return intermediate_path
end

return M
