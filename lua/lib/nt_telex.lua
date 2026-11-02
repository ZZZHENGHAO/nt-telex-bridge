-- Read-only TXi protocol and bounded polling; no firmware/calibration writes.
local M = {}

function M.decode(data)
    if type(data) ~= "table" or #data ~= 2 then return nil, "response length" end
    for i = 1, 2 do
        local b = data[i]
        if type(b) ~= "number" or b % 1 ~= 0 or b < 0 or b > 255 then
            return nil, "invalid byte"
        end
    end
    local n = data[1] * 256 + data[2]
    if n >= 32768 then n = n - 65536 end
    return n
end

function M.read(address, selector)
    if type(address) ~= "number" or address % 1 ~= 0 or address < 0x68 or address > 0x6f then
        return nil, "TXi address must be 0x68..0x6f"
    end
    if type(selector) ~= "number" or selector % 1 ~= 0 or selector < 0 or selector > 7 then
        return nil, "raw selector must be 0..7"
    end
    -- ONE payload byte: do not append a channel byte or TI.PARAM opcode.
    local ok, data = pcall(sendI2CGetter, address, 2, selector)
    if not ok then return nil, "getter raised error" end
    return M.decode(data)
end

function M.normalize(raw, low, high)
    if low == high then return nil end
    return math.max(0, math.min(1, (raw - low) / (high - low)))
end

function M.new(channels, firstSelector)
    return { channels = channels, firstSelector = firstSelector or 0, next = 1, elapsed = 0, wait = 0,
        attempts = 0, good = 0, errors = 0, failures = 0,
        values = {}, age = {}, lastError = "waiting", address = nil }
end

-- At most one synchronous getter per step; never replay missed ticks.
-- hz is PER CHANNEL: 8 channels at 50 Hz means 400 getters/second.
function M.tick(s, dt, address, hz, enabled)
    for i = 1, s.channels do s.age[i] = (s.age[i] or 0) + dt end
    if s.address ~= address then
        s.address, s.values, s.age = address, {}, {}
        s.elapsed, s.wait, s.next, s.failures = 0, 0, 1, 0
    end
    if not enabled then s.elapsed = 0; return nil end
    if s.wait > 0 then s.wait = math.max(0, s.wait - dt); return nil end
    s.elapsed = s.elapsed + dt
    local period = 1 / (hz * s.channels)
    if s.elapsed + 1e-9 < period then return nil end
    s.elapsed = s.elapsed % period
    local ch = s.next
    s.next = ch % s.channels + 1
    s.attempts = s.attempts + 1
    local raw, err = M.read(address, s.firstSelector + ch - 1)
    if raw == nil then
        s.errors, s.failures = s.errors + 1, s.failures + 1
        s.lastError = err
        if s.failures >= 3 then s.wait = 1 end
        return nil
    end
    s.good, s.failures, s.lastError = s.good + 1, 0, "OK"
    s.values[ch], s.age[ch] = raw, 0
    return ch, raw
end

return M
