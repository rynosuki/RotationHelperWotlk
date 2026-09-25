-- Offline test runner. From the repo root:
--   lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local T = require("testlib")

local SUITES = {
    "test_syntax",
    "test_core",
    "test_keybinds",
    "test_display",
}

for _, suite in ipairs(SUITES) do
    print(suite)
    require(suite)
end

print(("\n%d passed, %d failed"):format(T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
