return function(dispatcher)
    local UIControls = {}
    local utils = require("utils")

    local componentsList = {

    }

    local signalList = {

    }


    local function globalSignalID(signal)
        return signal.kind.."_"..signal.direction.."_"..tostring(signal.id)
    end

    local callbacksSet = {}

    local function createSigCallbackIDESender(signals)
        
        for _, signal in pairs(signals) do
            if callbacksSet[signal] ~= true then
                local h = function(value)
                    dispatcher.SendRPC({
                        command = "simulator_message",
                        kind = "state_update",
                        args = {
                            ts = dispatcher.FinalHAL.CurrentMicroseconds() / 1e6,
                            signals = {[globalSignalID(signal)]=value}
                        }
                    })
                end

                signal.onChanged(h)
                callbacksSet[signal] = true
            end
        end
    end

    local function createIDEMsgHandlerForSig(signal)
        if signal.direction == "output" then
            utils.errorExt("Cannot create IDE message handler for output signal, it is controlled by Actiongraph VM only", signal.id)
        end
        dispatcher.RPCMessageHandler(function (msg)
            if msg.command == "simulator_message" and msg.kind == 'simulator_ui_feedback' then
                if not msg.args then
                    return
                end
                local v = msg.args[globalSignalID(signal)]
                if v ~= nil then
                    signal.set(v)
                end
            end
        end)

    end

    local function addControlToList(name, signals, opts, isInteractive)
        local finalOpts = {}
        if type(opts) == "table" then
            for k, v in pairs(opts) do
                finalOpts[k] = v
            end
        end
        local signalOpts = {}

        for sig_label, signal in pairs(signals) do
            if signalList[globalSignalID(signal)] == nil then
                local sigOpts = {}
                for k, v in pairs(signal.opts) do
                    sigOpts[k] = v
                end
                signalList[globalSignalID(signal)] = {
                    index = signal.id,
                    signal_id = globalSignalID(signal),
                    kind = signal.kind,
                    direction = signal.direction,
                    options = sigOpts
                }
            end
            signalOpts[sig_label] = globalSignalID(signal)
        end


        table.insert(componentsList,
            {widget_type = name, signals = signalOpts, interactive = isInteractive, widget_params = finalOpts}
        )
    end

    function UIControls.SendUIConfig()
        dispatcher.SendRPC({
            command = "simulator_message",
            kind = 'ui_config',
            args = {controls = componentsList, signals = signalList}
        })
    end

    function UIControls.Switch(signal, opts)
        createIDEMsgHandlerForSig(signal)
        createSigCallbackIDESender({signal=signal})
        addControlToList("Switch",  {signal=signal}, opts, true)
    end

    function UIControls.Key(signal, opts)
        createIDEMsgHandlerForSig(signal)
        createSigCallbackIDESender({signal=signal})
        addControlToList("Key",  {signal=signal}, opts, true)
    end

    function UIControls.Gauge(signal, opts)
        createIDEMsgHandlerForSig(signal)
        createSigCallbackIDESender({signal=signal})
        addControlToList("Gauge",  {signal=signal}, opts, true)
    end

    function UIControls.Bulb(signal, opts)
        createSigCallbackIDESender({signal=signal})
        addControlToList("Bulb",  {signal=signal}, opts, false)
    end

    function UIControls.Graph(signals, opts)
        createSigCallbackIDESender(signals)
        addControlToList("Graph", signals, opts, false)
    end

    function UIControls.Meter(signal, opts)
        createSigCallbackIDESender({signal=signal})
        addControlToList("Meter", {signal=signal}, opts, false)
    end

    function UIControls.RGB_LED(signals, opts)
        if signals['red'] == nil and  signals['green'] == nil and  signals['blue'] == nil then
            utils.print("WARNING: LED control color channels are not set")
        end
        createSigCallbackIDESender(signals)
        addControlToList("RGB_LED", signals, opts, false)
    end

    function UIControls.Servo(signal, opts)
        createSigCallbackIDESender({signal=signal})
        addControlToList("Servo", {signal=signal}, opts, false)
    end


    return UIControls
end