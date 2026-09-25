-- Offline test runner. From the repo root:
--   lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local T = require("testlib")

local SUITES = {
    "test_syntax",
    "test_core",
    "test_keybinds",
    "test_display",
    "test_state",
    "test_apl",
    "test_engine",
    "test_frost",
    "test_unholy",
    "test_predict",
    "test_targets",
    "test_options",
    "test_skin",
    "test_perf",
    "test_errors",
    "test_latency",
    "test_waste",
    "test_interrupt",
    "test_specprofiles",
    "test_mouse_procs",
    "test_phase_a",
}

for _, suite in ipairs(SUITES) do
    print(suite)
    require(suite)
end

print(("\n%d passed, %d failed"):format(T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
