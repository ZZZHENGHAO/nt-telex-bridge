-- TXi Knob 1 probe
-- Read one TXi source at 50 Hz, initially Knob 1. No output buses or parameter writes.
local txi = require("nt_telex")
return {
    name = "TXi probe",
    author = "nt-telex-bridge",
    init = function(self)
        self.poll = txi.new(1)
        self.low, self.high, self.source = nil, nil, nil
        return { inputs = 0, outputs = 0, parameters = {
            { "Poll", 0, 1, 1 },
            { "TXi address", 104, 111, 104 },
            { "Source (1-8)", 1, 8, 1 },
        } }
    end,
    step = function(self, dt)
        local address = self.parameters[2]
        local source = self.parameters[3]
        if self.poll.address ~= address or self.source ~= source then
            self.poll = txi.new(1, source - 1)
            self.low, self.high, self.source = nil, nil, source
        end
        local _, raw = txi.tick(self.poll, dt, address, 50, self.parameters[1] == 1)
        if raw ~= nil then
            self.low = math.min(self.low or raw, raw)
            self.high = math.max(self.high or raw, raw)
        end
        return {}
    end,
    draw = function(self)
        local p = self.poll
        local raw = p.values[1]
        local status = self.parameters[1] == 0 and "PAUSED" or p.lastError
        drawText(2, 24, string.format("Source %d raw: %s", self.parameters[3], tostring(raw or "--")))
        drawTinyText(2, 35, string.format("min %s max %s age %.2fs",
            tostring(self.low or "--"), tostring(self.high or "--"), p.age[1] or 0))
        drawTinyText(2, 46, string.format("calls %d valid %d errors %d", p.attempts, p.good, p.errors))
        drawTinyText(2, 58, string.format("0x%02X 50Hz %s", self.parameters[2], status))
    end,
}
