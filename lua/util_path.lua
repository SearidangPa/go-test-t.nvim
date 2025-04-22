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

  -- Find the first two path segments
  local segments = {}
  for segment in relative_path:gmatch('[^' .. path_sep .. ']+') do
    table.insert(segments, segment)
    if #segments == 2 then
      break
    end
  end

  if #segments == 0 then
    return ''
  elseif #segments == 1 then
    return '.' .. path_sep .. segments[1]
  else
    return '.' .. path_sep .. segments[1] .. path_sep .. segments[2]
  end
end

return M
