local utils = require("utils")

return function (rpc)
    local handlers = {
        HandleRawDebugMessage_handlers = {},
        Tick_handlers = {},

        AnalogInputSignalValue_handlers = {},
        DigitalInputSignalValue_handlers = {},
        SetAnalogOutputSignalValue_handlers = {},
        SetDigitalOutputSignalValue_handlers = {},

        StdInMessageHandlers = {},

        HALRequestHandlers = {}
    }

    function handlers.Register_HandleRawDebugMessage(id, f)
        if handlers.HandleRawDebugMessage_handlers[id] ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.HandleRawDebugMessage_handlers[id]  = f
    end

    function handlers.Register_HALRequest(requestID, f)
        if handlers.HALRequestHandlers[requestID] ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.HALRequestHandlers[requestID] = f
    end



    function handlers.Register_ReadPersistentMemory(f)
        if handlers.ReadPersistentMemory ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.ReadPersistentMemory = f
    end

    function handlers.Register_WritePersistentMemory(f)
        if handlers.WritePersistentMemory ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.WritePersistentMemory = f
    end

    function handlers.Register_WriteSerial(f)
        if handlers.WriteSerial ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.WriteSerial = f
    end

    function handlers.Register_SerialBuf(f)
        if handlers.SerialBuf ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.SerialBuf = f
    end

    function handlers.Register_SerialAvailable(f)
        if handlers.SerialAvailable ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.SerialAvailable = f
    end

    function handlers.Register_Tick(f)
        table.insert(handlers.Tick_handlers, f)
    end

    function handlers.Register_CurrentMicroseconds(f)
        if handlers.CurrentMicroseconds ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.CurrentMicroseconds = f
    end

    function handlers.Register_CurrentMicrosecondsPrecise(f)
        if handlers.CurrentMicrosecondsPrecise ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.CurrentMicrosecondsPrecise = f
    end

    function handlers.Register_RobotUniqueSerialNumber(f)
        if handlers.RobotUniqueSerialNumber ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.RobotUniqueSerialNumber = f
    end

    function handlers.Register_AnalogInputSignalValue(id, f)
        if handlers.AnalogInputSignalValue_handlers[id] ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.AnalogInputSignalValue_handlers[id]  = f
    end

    function handlers.Register_DigitalInputSignalValue(id, f)
        if handlers.DigitalInputSignalValue_handlers[id] ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.DigitalInputSignalValue_handlers[id]  = f
    end

    function handlers.Register_SetAnalogOutputSignalValue(id, f)
        if handlers.SetAnalogOutputSignalValue_handlers[id] ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.SetAnalogOutputSignalValue_handlers[id]  = f
    end

    function handlers.Register_SetDigitalOutputSignalValue(id, f)
        if handlers.SetDigitalOutputSignalValue_handlers[id] ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.SetDigitalOutputSignalValue_handlers[id]  = f
    end



    function handlers.Register_GetTimersInterruptsState(f)
        if handlers.GetTimersInterruptsState ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.GetTimersInterruptsState = f
    end
    function handlers.Register_SetTimersInterruptsState(f)
        if handlers.SetTimersInterruptsState ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.SetTimersInterruptsState = f
    end
    function handlers.Register_SetTimerCallback(f)
        if handlers.SetTimerCallback ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.SetTimerCallback = f
    end
    function handlers.Register_ClearTimer(f)
        if handlers.ClearTimer ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.ClearTimer = f
    end
    function handlers.Register_SetTimerFrequency(f)
        if handlers.SetTimerFrequency ~= nil then
            utils.errorExt("Duplicate handler")
        end
        handlers.SetTimerFrequency = f
    end

    function handlers.RPCMessageHandler(f)
        table.insert(handlers.StdInMessageHandlers, f)
    end

    function handlers.SendRPC(req)
        rpc:Send(req)
    end

    handlers.FinalHAL = {
        HandleRawDebugMessage = function(id, data)
            if handlers.HandleRawDebugMessage_handlers[id] == nil then
                utils.print("HandleRawDebugMessage stub called: ", id, data)
                return
            end
            return handlers.HandleRawDebugMessage_handlers[id](data)
        end,
        HALRequest = function(requestType, data)
            if handlers.HALRequestHandlers[requestType] == nil then return 1, "" end
        
            return handlers.HALRequestHandlers[requestType](requestType, data)
        end,
        AnalogInputSignalValue = function(id)
            if handlers.AnalogInputSignalValue_handlers[id] == nil then
                utils.print("AnalogInputSignalValue stub called:", id)
                return 0
            end
            return handlers.AnalogInputSignalValue_handlers[id]()
        end,
        DigitalInputSignalValue = function(id)
            if handlers.DigitalInputSignalValue_handlers[id] == nil then
                utils.print("DigitalInputSignalValue stub called: ", id)
                return false
            end
            return handlers.DigitalInputSignalValue_handlers[id]()
        end,
        SetAnalogOutputSignalValue = function(id, value)
            if handlers.SetAnalogOutputSignalValue_handlers[id] == nil then
                utils.print("SetAnalogOutputSignalValue stub called:", id, value)
                return false
            end
            return handlers.SetAnalogOutputSignalValue_handlers[id](value)
        end,
        SetDigitalOutputSignalValue = function(id, value)
            if handlers.SetDigitalOutputSignalValue_handlers[id] == nil then
                utils.print("SetDigitalOutputSignalValue stub called:", id, value)
                return false
            end
            return handlers.SetDigitalOutputSignalValue_handlers[id](value)
        end,

        ReadPersistentMemory = function(offset, size)
            if handlers.ReadPersistentMemory then
                return handlers.ReadPersistentMemory(offset, size)
            end

            utils.print("ReadPersistentMemory stub called: ", offset, size)
            return false, ""
        end,
        WritePersistentMemory = function(offset, data)
            if handlers.WritePersistentMemory then
                return handlers.WritePersistentMemory(offset, data)
            end

            utils.print("WritePersistentMemory stub called:", offset, string.len( data ))
            return true
        end,
        WriteSerial = function(data)
            if handlers.WriteSerial then
                return handlers.WriteSerial(data)
            end
            utils.print("WriteSerial stub called: ", data)
            return false
        end,
        SerialBuf = function()
            if handlers.SerialBuf then
                return handlers.SerialBuf()
            end
            utils.print("SerialBuf stub called")
            return ""
        end,
        SerialAvailable = function()
            if handlers.SerialAvailable then
                return handlers.SerialAvailable()
            end
            utils.print("SerialAvailable stub called")
            return 0
        end,
        Tick = function()
            if #handlers.Tick_handlers > 0 then
                for _, h in ipairs(handlers.Tick_handlers) do
                    h()
                end
                return
            end
            utils.print("Tick stub called")
        end,
        CurrentMicroseconds  = function()
            if handlers.CurrentMicroseconds then
                return handlers.CurrentMicroseconds()
            end
            utils.print("CurrentMicroseconds stub called")
            return 0
        end,
        CurrentMicrosecondsPrecise  = function()
            if handlers.CurrentMicrosecondsPrecise then
                return handlers.CurrentMicrosecondsPrecise()
            end
            utils.print("CurrentMicrosecondsPrecise stub called")
            return 0
        end,
        RobotUniqueSerialNumber = function()
            return handlers.RobotUniqueSerialNumber()
        end,
        GetTimersInterruptsState = function()
            return handlers.GetTimersInterruptsState()
        end,
        SetTimersInterruptsState = function(v)
            return handlers.SetTimersInterruptsState(v)
        end,
        SetTimerCallback = function(timerObj)
            return handlers.SetTimerCallback(timerObj)
        end,
        ClearTimer = function(timerObj)
            return handlers.ClearTimer(timerObj)
        end,
        SetTimerFrequency = function(id, freq)
            return handlers.SetTimerFrequency(id, freq)
        end,
    }

    function handlers.HandleRPC(msg)
        for _, h in ipairs(handlers.StdInMessageHandlers) do
            h(msg)
        end
    end

    local function signalObjCreator(id, kind, direction, opts, out_filter)
        if type(opts) ~= "table" then
            opts = {}
        end
        if direction == "input" then
            if kind == "digital" then
                if type(opts.initial_value) ~= "boolean" then
                    opts.initial_value = false
                end
            elseif kind == "analog" then
                if type(opts.initial_value) ~= "number" then
                    opts.initial_value = 0
                end
            end
        else
            opts.initial_value = "n/a"
        end
        local ret = {
            id = id,
            kind = kind,
            direction = direction,
            opts = opts,
            index = id,
            state = opts.initial_value,
            prevState = nil,
            callbacks = {},
            out_filter = out_filter
        }
        if direction == "input" then
            if kind == "digital" then
                handlers.Register_DigitalInputSignalValue(id, function()
                    return ret.state
                end)
            
            elseif kind == "analog" then
                handlers.Register_AnalogInputSignalValue(id, function()
                    return ret.state
                end)
            end
        elseif direction == "output" then
            if kind == "digital" then
                handlers.Register_SetDigitalOutputSignalValue(id, function(v)
                    if ret.out_filter then
                        v = ret.out_filter(v)
                    end
                    ret.state = v
                    if ret.prevState ~= ret.state then
                        for _, cb in ipairs(ret.callbacks) do
                            cb(v)
                        end
                    end
                    ret.prevState = ret.state
                    return true
                end)
            
            elseif kind == "analog" then
                handlers.Register_SetAnalogOutputSignalValue(id, function(v)
                    if ret.out_filter then
                        v = ret.out_filter(v)
                    end
                    ret.state = v
                    if ret.prevState ~= ret.state then
                        for _, cb in ipairs(ret.callbacks) do
                            cb(v)
                        end
                    end
                    ret.prevState = ret.state
                    return true
                end)
            end
        end
    
        function ret.get()
            return ret.state
        end
        function ret.set(val)
            if direction == "output" then
                utils.errorExt("Cannot set output signal value from script logic, it is done by Actiongraph VM only", id, val)
            end
            if kind == "digital" then
                if type(val) ~= "boolean" then
                    utils.print("Digital signal value must be boolean", id, val)
                    return
                end
            elseif kind == "analog" then
                if type(val) ~= "number" then
                    utils.print("Analog signal value must be numeric", id, val)
                    return
                end
            end
            ret.state = val
            if ret.prevState ~= ret.state then
                for _, cb in ipairs(ret.callbacks) do
                    cb(val)
                end
            end
            ret.prevState = ret.state
        end
        function ret.onChanged(f)
            table.insert(ret.callbacks, f)
        end

        return ret
    end

    handlers.InputDigitalSignal = function(id, opts)
        return signalObjCreator(id, "digital", "input", opts)
    end

    handlers.OutputDigitalSignal = function(id, opts, out_filter)
        return signalObjCreator(id, "digital", "output", opts, out_filter)
    end

    handlers.InputAnalogSignal = function(id, opts)
        return signalObjCreator(id, "analog", "input", opts)
    end

    handlers.OutputAnalogSignal = function(id, opts, out_filter)
        return signalObjCreator(id, "analog", "output", opts, out_filter)
    end

    rpc:addCallback(handlers.HandleRPC)
    return handlers
end