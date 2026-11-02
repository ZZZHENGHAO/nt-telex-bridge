-- Desktop protocol/scheduler simulation. Does NOT validate real I2C transactions.
package.path = "lua/lib/?.lua;" .. package.path
local txi = require("nt_telex")
local checks = 0
local function eq(a, b)
    checks = checks + 1
    assert(a == b, string.format("expected %s, got %s", tostring(b), tostring(a)))
end
for _, case in ipairs({
    {0, 0, 0}, {0x1f, 0xff, 8191}, {0x3f, 0xff, 16383},
    {0x40, 0, 16384}, {0x7f, 0xff, 32767},
    {0x80, 0, -32768}, {0xc0, 0, -16384}, {0xff, 0xff, -1},
}) do eq(txi.decode({case[1], case[2]}), case[3]) end
for _, bad in ipairs({false, 1, "bad", {}, {1}, {1, 2, 3}, {256, 0}, {-1, 0}, {0.5, 0}}) do
    eq(txi.decode(bad), nil)
end
eq(txi.decode(nil), nil)
eq(txi.normalize(0, 0, 8191), 0)
eq(txi.normalize(8191, 0, 8191), 1)
eq(txi.normalize(-10, 0, 8191), 0)
eq(txi.normalize(9000, 0, 8191), 1)
eq(txi.normalize(0, -100, 100), 0.5)
eq(txi.normalize(100, 100, -100), 0)
eq(txi.normalize(10, 10, 10), nil)

local calls, selectors = 0, {}
sendI2CGetter = function(address, bytes, ...)
    eq(address, 0x68); eq(bytes, 2); eq(select("#", ...), 1)
    local selector = ...
    selectors[#selectors + 1] = selector
    calls = calls + 1
    return {0, selector}
end
eq(txi.read(0x67, 0), nil); eq(txi.read(0x68, 8), nil)
eq(calls, 0)
local s = txi.new(1)
for _ = 1, 1000 do txi.tick(s, 0.001, 0x68, 50, true) end
eq(calls, 50); eq(s.good, 50); eq(s.values[1], 0)
calls, selectors = 0, {}
s = txi.new(8)
for _ = 1, 1000 do txi.tick(s, 0.001, 0x68, 50, true) end
eq(calls, 400)
for i, v in ipairs(selectors) do eq(v, (i - 1) % 8) end
local old = calls
txi.tick(s, 1, 0x68, 50, true)
eq(calls, old + 1) -- no catch-up burst
txi.tick(s, 1, 0x68, 50, false)
eq(calls, old + 1)
txi.tick(s, 0.001, 0x69, 50, false)
eq(s.values[1], nil) -- address change cannot reuse an old device's values

sendI2CGetter = function() calls = calls + 1; error("NACK simulation") end
calls = 0; s = txi.new(1)
for _ = 1, 1000 do txi.tick(s, 0.001, 0x68, 50, true) end
eq(calls, 3); eq(s.errors, 3); eq(s.good, 0)
sendI2CGetter = function() return {0x12} end
eq(txi.read(0x68, 0), nil)
sendI2CGetter = function() return {0xff, 0xff} end
eq(txi.read(0x68, 0), -1) -- valid encoding is NOT proof of a healthy bus

-- Minimal host callbacks, matching documented Lua Script shape.
kLinear = 1
drawText = function() end
drawTinyText = function() end
local function loadScript(path)
    local script = dofile(path)
    local spec = script:init()
    script.parameters = {}
    for i, p in ipairs(spec.parameters) do script.parameters[i] = p[4] end
    return script, spec
end
sendI2CGetter = function(_, _, selector)
    return selector < 4 and {0x1f, 0xff} or {0xc0, 0}
end
local probe, spec = loadScript("lua/txi_probe.lua")
eq(spec.outputs, 0)
for _ = 1, 20 do probe:step(0.001) end
eq(probe.low, 8191); eq(probe.high, 8191)
probe:draw()
local selected
sendI2CGetter = function(_, _, selector) selected = selector; return {0xc0, 0} end
probe.parameters[3] = 5
for _ = 1, 20 do probe:step(0.001) end
eq(selected, 4); eq(probe.low, -16384); eq(probe.high, -16384)
sendI2CGetter = function(_, _, selector)
    return selector < 4 and {0x1f, 0xff} or {0xc0, 0}
end
local bridge, bs = loadScript("lua/txi_bridge.lua")
eq(#bs.outputs, 8)
for _ = 1, 100 do bridge:step(0.001) end
for i = 1, 8 do eq(bridge.out[i], 0) end -- not armed
bridge.parameters[4], bridge.parameters[5] = 0, 1
bridge.parameters[7] = 8191 -- measured K1 maximum
bridge:step(0.001)
eq(bridge.out[1], 10); eq(bridge.out[5], 0)
bridge.parameters[1] = 0
for _ = 1, 300 do bridge:step(0.001) end
eq(bridge.out[1], 10) -- explicit hold policy while paused
bridge.parameters[1] = 1
sendI2CGetter = function() return nil end
for _ = 1, 300 do bridge:step(0.001) end
eq(bridge.out[1], 10); assert(bridge.poll.age[1] >= 0.25)
bridge.parameters[5] = 0
bridge:step(0.001); eq(bridge.out[1], 0)
bridge.parameters[1], bridge.parameters[5] = 1, 1
bridge.parameters[2] = 105
bridge:step(0.001); eq(bridge.out[1], 0)
bridge:draw()
print(string.format("PASS: %d assertions (Lua %s); hardware NOT tested", checks, _VERSION))
