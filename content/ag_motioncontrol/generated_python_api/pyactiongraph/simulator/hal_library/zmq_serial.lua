local utils = require("utils")

local port = SerialTransport()
if not parameters.transport then
    utils.errorExt("parameter 'transport' required")
end
port:open(parameters.transport)

local accum = ""
simulator.Register_Tick(function ()
    accum = ""
    while true do
        local rcv = port:readData()
        if rcv ~= nil then
            -- utils.print("Received data", rcv)
            accum = accum..rcv
        else
            break
        end
    end
end)

simulator.Register_WriteSerial(function (data) --  +
    port:sendData(data)
    return true
end)

simulator.Register_SerialBuf(function () --  +
    -- utils.print("SerialBuf called")
    return accum
end)

simulator.Register_SerialAvailable(function () --  +
    -- utils.print("SerialAvailable called")
    return string.len(accum)
end)