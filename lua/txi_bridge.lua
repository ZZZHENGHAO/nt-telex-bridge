-- TXi eight controls
-- Four knobs and four CVs to internal buses for native NT CV parameter mapping.
local txi = require("nt_telex")
local names = { "K1", "K2", "K3", "K4", "CV1", "CV2", "CV3", "CV4" }
return {
    name = "TXi bridge",
    author = "nt-telex-bridge",
    init = function(self)
        self.poll = txi.new(8)
        self.filtered, self.out, self.lastAddress = {}, {}, nil
        local params = {
            { "Poll", 0, 1, 1 },
            { "TXi address", 104, 111, 104 },
            { "Hz per channel", 10, 50, 50 },
            { "Smoothing ms", 0, 500, 30 },
            { "Outputs armed", 0, 1, 0 },
        }
        for i = 1, 8 do
            -- Deliberately provisional until the probe measures this hardware.
            params[#params + 1] = { names[i] .. " raw low", -32768, 32767, i <= 4 and 0 or -16384 }
            params[#params + 1] = { names[i] .. " raw high", -32768, 32767, 16383 }
        end
        for i = 1, 8 do self.out[i] = 0 end
        return { inputs = 0,
            outputs = { kLinear, kLinear, kLinear, kLinear, kLinear, kLinear, kLinear, kLinear },
            outputNames = names, parameters = params }
    end,
    step = function(self, dt)
        local p, s = self.parameters, self.poll
        if self.lastAddress ~= p[2] then
            self.filtered = {}
            for i = 1, 8 do self.out[i] = 0 end
            self.lastAddress = p[2]
        end
        txi.tick(s, dt, p[2], p[3], p[1] == 1)
        local alpha = p[4] == 0 and 1 or 1 - math.exp(-dt / (p[4] / 1000))
        for i = 1, 8 do
            local raw = s.values[i]
            local low, high = p[6 + 2 * (i - 1)], p[7 + 2 * (i - 1)]
            -- Freeze stale/disabled channels. Hold last output; do not jump to zero.
            -- Explicitly disarming DOES zero the outputs (see README).
            if p[5] == 0 then
                self.out[i], self.filtered[i] = 0, nil
            elseif p[1] == 1 and raw ~= nil and (s.age[i] or 1) < 0.25 then
                local n = txi.normalize(raw, low, high)
                if n then
                    local previous = self.filtered[i] or n
                    local v = previous + alpha * (n - previous)
                    self.filtered[i] = v
                    local volts = v * 10
                    if math.abs(volts - self.out[i]) >= 0.001 then self.out[i] = volts end
                end
            end
        end
        return self.out
    end,
    draw = function(self)
        local s = self.poll
        for i = 1, 8 do
            local x, y = i <= 4 and 2 or 130, 24 + ((i - 1) % 4) * 9
            drawTinyText(x, y, string.format("%s %s%s", names[i],
                tostring(s.values[i] or "--"), (s.age[i] or 1) >= 0.25 and " stale" or ""))
        end
        drawTinyText(2, 63, string.format("%s valid %d err %d %s",
            self.parameters[5] == 1 and "ARMED" or "DISARMED", s.good, s.errors, s.lastError))
    end,
}
