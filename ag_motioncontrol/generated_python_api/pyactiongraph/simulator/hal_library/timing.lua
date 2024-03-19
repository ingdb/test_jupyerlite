local utils = require("utils")

local simTime = 0

simulator.Register_CurrentMicroseconds(function ()
    return simTime * 1000
end)

simulator.Register_CurrentMicrosecondsPrecise(function ()
    return simTime * 1000
end)
local timerInterrupts = {}

simulator.Register_Tick(function ()
    simTime = simTime + 1
    for k, tmr in pairs(timerInterrupts) do
        local requiredPulses = math.floor(tmr.freq * (simTime/1000.0 - tmr.prev_ts_s))
        if requiredPulses >= 1 then
            for i = 1,requiredPulses do
                tmr.obj:call()
            end
            tmr.prev_ts_s = tmr.prev_ts_s + requiredPulses/tmr.freq
        end
    end
end)

local interruptsState = 1

simulator.Register_GetTimersInterruptsState(function()
    return interruptsState
end)

simulator.Register_SetTimersInterruptsState(function(v)
    interruptsState = v
    return 1
end)
simulator.Register_SetTimerCallback(function (timerObj)
    timerInterrupts[timerObj:id()] = {obj=timerObj, freq = 0, prev_ts_s=simTime/1000.0}
    -- utils.print("Timer callback set", timerObj:id())
    return timerObj:id()
end)

simulator.Register_ClearTimer(function (timerObj)
    timerInterrupts[timerObj:id()] = nil
    -- utils.print("Timer is cleared", timerObj:id())
    return 1
end)

simulator.Register_SetTimerFrequency(function (id, freq)
    timerInterrupts[id].freq = freq
    -- utils.print("Freq changed", id, freq)
    return 1
end)