-- Simple mutex implementation
local Mutex = {}
Mutex.__index = Mutex

function Mutex.new() return setmetatable({ locked = false }, Mutex) end

function Mutex:lock()
  while self.locked do
    -- Yield to allow other coroutines/threads to run
    coroutine.yield()
  end
  self.locked = true
  return true
end

function Mutex:unlock()
  self.locked = false
  return true
end
