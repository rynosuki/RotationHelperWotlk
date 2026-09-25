local T = require("testlib")

-- Compile (but don't run) every .lua file in the addon, libraries included.
local listing = io.popen('dir /s /b "RotationHelper\\*.lua" 2>nul')
for path in listing:lines() do
    path = path:gsub("\r", "")
    T.test("compiles " .. path:match("RotationHelper[\\/].*$"), function()
        local chunk, err = loadfile(path)
        T.truthy(chunk, err)
    end)
end
listing:close()
