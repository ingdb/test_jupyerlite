local MINIMUM_REQUIRED_FW_MAJOR_VERSION = 31
local json = require'json'
local utils = require("utils")
local mc = {}
local Vector = require'vector'
local OrderedTable = require"orderedtable"

local scheduler = require"scheduler"
require"custom_lowlevel_functions"
SerialTransport = require"transport_wrapper".SerialTransport

local actiongraph_rpc_proto = require"actiongraph_rpc_proto"

mc.debug_serial = false

mc.SerializedParameterByteLength = 60


function mc.CreateRobot(id, serial, fixedTransportConfig, forceReupload, IgnoreSerial)
    local r = {
        ID = id,
        Serial = serial,
        FixedTransport = fixedTransportConfig,
        ForceReupload = forceReupload == true,
        IgnoreSerial = IgnoreSerial == true or false
    }
    mc.__index = mc
    setmetatable(r, mc)

    r.currentSerialTransport = SerialTransport()
    r.debug = false
    r.conj_group_index = 0
    r.actionCreateResponseHook = function(args) end
    r.connectionCreateResponseHook = function(args) end
    r.cmdGraphStartResponseHook = function(args) end
    r.setEntryResponseHook = function(args) end
    r.cmdGraphClearResponseHook = function(args) end
    r.paramSetResponseHooks = {}
    r.paramValueResponseHooks = {}
    r.stateHashResponseHook = function(args) end
    r.movableReachabilityTestResultHook = function(args) end
    r.actions_by_ID = {}
    r.hw_modules_by_ID = {}
    r.next_action_id = 0
    r.params_by_ID = {}
    r.next_param_id = 0
    r.next_unique_event_id = 0
    r.next_unique_hw_id = 0
    r.lastReceivedVersionInfo = nil
    r.halDebugMessageListeners = {}

    r.saveParamDBResponseHook = function(args) end
    r.loadParamDBResponseHook = function(args) end
    r.hardwareStopResponseHook = function(args) end

    r.hardwareSetResponseHook = function(args) end

    r.prevHeartbeatSend = millis()
    r.prevHeartbeatReceived = millis()
    r.isReadyAndSynced = false
    r.isConnected = false

    r.actionsToUpload = {}
    r.connectionsToUpload = {}
    r.paramsToUpload = {}
    r.paramsStateHashes = {}
    r.hardwareToUpload = {}

    r.actionErrorCallbacks = {}

    r.actionClasses = mc.initActionClasses(r)

    r.rpc_handlers = {
        default = mc.RPCHandler(actiongraph_rpc_proto.parseRPCEndpoints(mc.rpc_default_endpoints(r))),
        actionClassesHandler = mc.RPCHandler(mc.parseActionClassesRPCEndpoints(r.actionClasses)),
    }

    r.readyCallbacks = {}
    r.diconnectedEventCallbacks = {}

    r.serialSender = function (data)
        local result, err = pcall(function ()
            r.currentSerialTransport:sendData(data)
        end)
        if result == false then
            r:robotInteractionError(tostring(err))
        end
    end

    r.halRequestLock = scheduler.NewLock()
    r.halRequestResultHook = nil
    
    r.mainTask = scheduler.addTask(function() -- TODO need to be closed from somewhere
        r:MainCoroutine()
    end, "robot "..id.." task")
    return r
end

function mc:Shutdown()
    self:Disconnect()
    if self.robotTransportReaderTask ~= nil then self.robotTransportReaderTask.cancel() end
    self.mainTask.cancel()
end

function mc:SetFixedTransport(newconf)
    utils.info(5, "Adjusted transport for robot ", self.ID,  self.Serial, newconf)
    self.FixedTransport = newconf
    self:Disconnect()
end

function mc.createJSONSender(self, name)
    return function (args) 
        local ob = {ID = self.ID, rpc_name = name, args = args}
        local s = json.stringify(ob)
        utils.print(s)
    end
end

function mc:actionResponseHandler(args)
    self.actionCreateResponseHook(args)
end

function mc:connectionResponseHandler(args)
    self.connectionCreateResponseHook(args)
end

function mc:startCMDGraphResponseHandler(args)
    self.cmdGraphStartResponseHook(args)
end

function mc:setEntryHandler(args)
    self.setEntryResponseHook(args)
end

function mc:loopErrorHandler(args)
    utils.print("DETECTED LOOP PROBLEM at: ", args.ts, "delta:", args.defected_loop_step_ts)
    utils.logError("DETECTED LOOP PROBLEM at: ", args.ts, "delta:", args.defected_loop_step_ts)
end

function mc:clearCMDGraphResponseHandler(args)
    self.cmdGraphClearResponseHook(args)
end

function mc:actionErrorHandler(args)
    local ob = {rpc_name = "ACTION_ERROR", args = args, ID = self.ID}
    local action = self:FindActionByID(args["action_id"])
    local actionAlias = "UNKNOWN_ACTION"..args["action_id"]
    if action ~= nil then actionAlias = action.alias end
    local logStr = string.format("'<%s>%s' error: '%s' at %s", self.ID, actionAlias, mc.errorsTable[args["error"]], args.ts/1e6)
    utils.print(logStr)
    utils.logError(logStr)
    if self.actionErrorCallbacks[args["action_id"]] ~= nil then
        for _, clb in ipairs(self.actionErrorCallbacks[args["action_id"]]) do
            clb(mc.errorsTable[args["error"]], args.ts)
        end
    end
end

function mc:ConnectedRobotVersionInfo()
    return self.lastReceivedVersionInfo
end
function mc:heartbeatHandler(args)
    self.lastReceivedVersionInfo = utils.tableclone(args)
    self.prevHeartbeatReceived = millis()
    -- print("@@@@@@@@@@@  HB RECEIVED @@@@@@@@@@@@")
end
function mc:legacyHeartbeatHandler1(args)
    self.lastReceivedVersionInfo = utils.tableclone(args)
    self.prevHeartbeatReceived = millis()
end
function mc:paramValueRcvHandler(args)
    if self.paramValueResponseHooks[args.param_id] ~= nil then
        for h, _ in pairs(self.paramValueResponseHooks[args.param_id]) do
            h(args)
        end
    end
end

function mc:getParamErrorHandler(args)
    local ob = {rpc_name = "GET_PARAM", args = args, ID = self.ID}
    local s = json.stringify(ob)
    utils.print(s)
    utils.logError(s)
end

function mc:setParamErrorHandler(args)
    if args["error"] ~= 1 then
        local s = string.format( "Param '%s' set error: '%s'", self.params_by_ID[args["param_id"]].alias, mc.errorsTable[args["error"]] )
        utils.print(s)
        utils.logError(s)
    end
    if self.paramSetResponseHooks[args["param_id"]] == nil then
        utils.logError("No response callback for parameter " .. self.params_by_ID[args["param_id"]].alias )
    end
    for h, _ in pairs(self.paramSetResponseHooks[args.param_id]) do
        h(args)
    end
end

function mc:halRequestResultHandler(args)
    if self.halRequestResultHook ~= nil then
        self.halRequestResultHook(args)
    else
        utils.logError("No response callback for HAL request ", json.stringify(args))
    end
end

function mc:paramEventHandler(args)

end


function mc:saveParamDBHandler(args)
    self.saveParamDBResponseHook(args)
end
function mc:loadParamDBHandler(args)
    self.loadParamDBResponseHook(args)
end

function mc:hardwareStoppedHandler(args)
    self.hardwareStopResponseHook(args)
end

function mc:hardwareSetResultHandler(args)
    self.hardwareSetResponseHook(args)
end

function mc:halDebugMessageHandler(args) 
    if args["id"] == 255 then
        if args["size"] ~= 15 then
            error("HERE")
        end
        local data = args["data"]
        local isSkipped = parseBinaryRPCargument(data:sub(1, 1), "ui1")
        local reasonActionIndex = parseBinaryRPCargument(data:sub(2, 3), "ui2")
        local when = parseBinaryRPCargument(data:sub(4, 4), "ui1")
        local trgActionIndex = parseBinaryRPCargument(data:sub(5, 6), "ui2")
        local targetTask = parseBinaryRPCargument(data:sub(7, 7), "ui1")
        local ts = parseBinaryRPCargument(data:sub(8, 15), "ui8")
        local reasonMap = {[0]="STARTED", [1]="STOPPED", [2]="ERRED"}
        local taskMap = {[0]="START", [1]="STOP", [2]="CANCEL"}
        utils.print(string.format( "Connection %s at %s: when %s %s do %s %s", 
            isSkipped == 1 and "skipped  " or "triggered",
            ts/1000,
            self:FindActionByID(reasonActionIndex).alias:sub(-30, -1),
            reasonMap[when],
            taskMap[targetTask],
            self:FindActionByID(trgActionIndex).alias:sub(-30, -1)
        ))
    elseif args["id"] == 254 then
        if args["size"] ~= 12 then
            error("HERE")
        end
        local data = args["data"]
       
        local actionIndex = parseBinaryRPCargument(data:sub(1, 2), "ui2")
        local oldState = parseBinaryRPCargument(data:sub(3, 3), "ui1")
        local newState = parseBinaryRPCargument(data:sub(4, 4), "ui1")
        local ts = parseBinaryRPCargument(data:sub(5, 12), "ui8")
        local stateMap = {[0]="INIT", 
                          [1]="RUNNING", 
                          [2]="STOPPED", 
                          [3]="GOING_TO_RUN",
                          [4]="GOING_TO_STOP",
                          [5]="GOING_TO_CANCEL_DUE_ERROR",
                          [6]="RUNNING_STOPPED_RUNNING_TRANSITION",
                          [7]="STOPPED_RUNNING_STOPPED_TRANSITION"
                        }
            utils.print(string.format( "ActionNode %s  changed state: %s -> %s", 
            self:FindActionByID(actionIndex).alias:sub(-30, -1),
            -- ts/1000,
            stateMap[oldState],
            stateMap[newState]
        ))
    else
        if self.halDebugMessageListeners[args["id"]] == nil then return end
        for _, h in ipairs(self.halDebugMessageListeners[args["id"]]) do
            h(args["data"], args["size"])
        end
    end
end

function mc:loadedStateHashHandler(args)
    self.stateHashResponseHook(args)
end

function mc:movableReachabilityTestResultHandler(args)
    self.movableReachabilityTestResultHook(args)
end

mc.rpc_default_endpoints = function(self) return {
    {3, {{"error","e"} }, function(...) self:startCMDGraphResponseHandler(...) end},
    {4, { }, mc.createJSONSender(self, "STOP")},
    {18, { }, function(...) self:clearCMDGraphResponseHandler(...) end},

    {19, {{"action_id", "ui2"}, {"action_error","e"}, {"add_error", "e"} }, function(...) self:actionResponseHandler(...) end},
    
    {21, { {"action_id", "ui2"}, {"error","e"} },  mc.createJSONSender(self, "ACTION_REMOVE_RESULT")},
    {20, { {"src_action_id", "ui2"}, {"trg_action_id", "ui2"}, {"error","e"} }, function(...) self:connectionResponseHandler(...) end},
    {27, { {"action_id", "ui2"}, {"error","e"}, {"ts","ui8"} }, function(...) self:actionErrorHandler(...) end},
    {28, { {"hw_major_version", "ui2"}, {"hw_minor_version", "ui2"}, {"sw_major_version", "ui2"}, {"sw_minor_version", "ui2"}, {"robot_unique_id", "2a8"}}, function(...) self:heartbeatHandler(...) end},

    {32, { {"param_id", "ui2"}, {"locked", "ui1"}, {"is_set", "ui1"}, {"type", "ui1"}, {"size", "ui1"}, {"data", string.format("2a%s", mc.SerializedParameterByteLength)}  }, function(...) self:paramValueRcvHandler(...) end},
    {30, {{"param_id", "ui2"}, {"error", "e"}}, function(...) self:getParamErrorHandler(...) end},
    {31, {{"param_id", "ui2"}, {"error", "e"}}, function(...) self:setParamErrorHandler(...) end},
    {33, {{"param_id", "ui2"}, {"event", "e"}}, function(...) self:paramEventHandler(...) end},
    {37, { {"error","e"} }, function(...) self:saveParamDBHandler(...) end},
    {38, { {"error","e"} }, function(...) self:loadParamDBHandler(...) end},

    {39, { {"id", "ui2"}, {"hw_type", "ui1"}, {"error", "e"}}, function(...) self:hardwareSetResultHandler(...) end},
    {40, { {"id", "ui1"}, {"size", "ui2"}, {"data", "2a64"}}, function(...) self:halDebugMessageHandler(...) end},
    {43, { {"error","e"} }, function(...) self:hardwareStoppedHandler(...) end},
    {44, { {"error","e"}, {"state_hash", "2a8"}  }, function(...) self:loadedStateHashHandler(...) end},
    {45, { {"action_id","ui2"}, {"error","e"}  }, function(...) self:setEntryHandler(...) end},
    {50, { {"ts","ui8"}, {"defected_loop_step_ts","ui8"}}, function(...) self:loopErrorHandler(...) end},
    {52, { {"error","e"}, {"result","ui1"}}, function(...) self:movableReachabilityTestResultHandler(...) end},
    {53, { {"result", "ui1"}, {"requestType", "ui2"}, {"data", string.format("2a%s", mc.SerializedParameterByteLength)}, {"size", "ui2"}}, function(...) self:halRequestResultHandler(...) end}
} end

-- ACCORDING TO rpc.hpp
mc.rpc_senders = {
    REMOVE_ACTION=                              {17, { {"action_id", "ui2"} } },
    CLEAR=                                      {18, {  } },
    HEARTBEAT =                                 {28, { } },
    EVENT =                                     {0, {{"event_id", "ui2"}}},
    START_CMD_GRAPH=                            {3, {}},
    STOP=                                       {4, {}},
    
    GET_PARAM =                                 {30, { {"param_id", "ui2"}}},
    SET_PARAM =                                 {31, { {"param_id", "ui2"}, {"set", "ui1"}, {"type", "ui1"}, {"size", "ui1"}, {"data", string.format("2a%s", mc.SerializedParameterByteLength)}   }},

    ADD_CONNECTION=                             {5, { {"when", "e"}, {"source", "ui2"}, {"task", "e"}, {"target", "ui2"}, {"conjunctionGroupID", "si2"} } }, 
    REBOOT_TO_BOOTLOADER=                       {36, {}},
    SAVE_STATE=                                 {37, {}},

    SET_HARDWARE_MODULE =                       {39, { {"id", "ui2"}, {"hw_type", "ui1"}, {"start_now", "ui1"}, {"param_count", "ui1"} , {"param_ids", "2a64"}  }},
    HAL_DEBUG_MESSAGE =                         {40, { {"id", "ui1"}, {"size", "ui2"}, {"data", "2a32"}  }},
    ADD_ACTION =                                {42, { {"id", "ui2"}, {"act_type", "ui1"}, {"param_count", "ui1"} , {"param_ids", "2a64"}  }},
    STOP_HARDWARE=                                     {43, {}},
    GRAPH_STATE_HASH =                          {44, {}},
    SET_CMD_GRAPH_ENTRY =                       {45, {{"entry_node", "ui2"}}},
    POINT_IS_IN_MOVABLE_WORKING_AREA_TEST =     {52, {{"movable", "ui2"}, {"x", "f4"}, {"y", "f4"}, {"z", "f4"}}},
    HAL_REQUEST =                               {53, {{"requestType", "ui2"}, {"data", string.format("2a%s", mc.SerializedParameterByteLength)}, {"size", "ui2"}}},
}

--Actions shortcuts

-- MOVEMENT = MOVEMENT2 -- TEMPORARY HACK

mc.initActionClasses = function(self) return {
    DELAY =                        {name="Delay",                      act_type=0,  params={"delay"}, optional={}},
    PARAM_ASSIGNER =               {name="ParamAssigner",              act_type=1,  params={"param_from", "param_to"}, optional={}},
    MOVABLE_STATUS_SAVER =         {name="MovableStatusSaver",         act_type=2,  params={"movable", "x", "y", "z", "vx", "vy", "vz"}, optional={"x", "y", "z", "vx", "vy", "vz"}},
    DIGITAL_SIGNAL_VALUE_SAVER =   {name="DigitalSignalValueSaver",    act_type=3,  params={"signal", "param"}, optional={}},
    ANALOG_SIGNAL_VALUE_SAVER =    {name="AnalogSignalValueSaver",     act_type=4,  params={"signal", "param"}, optional={}},
    PC_MSG_WAITER =                {name="PCMsgWaiter",                act_type=5,  params={"event"}, optional={}},
    PC_MSG_EMITTER =               {name="PCMsgEmitter",               act_type=6,  params={"event"}, optional={},
                                        rpc_handler = {0, {{"event", "ui2"}, {"ts", "ui8"} }, function(args) 
                                        end},
                                    },
    DIGITAL_SIGNAL_VALUE_WAITER =  {name="DigitalSignalValueWaiter",   act_type=7,  params={"signal", "value"}, optional={}},
    CALIBRATER =                   {name="Calibrater",                 act_type=8,  params={"movable", "x", "y", "z"}, optional={"x", "y", "z"}},
    MOVABLE_STATUS_REPORTER =      {name="MovableStatusReporter",      act_type=9, 
                                    params={"movable", "event", "ignore_movable_errors", "report_native_coord"}, optional={"ignore_movable_errors", "report_native_coord"},
                                        rpc_handler = {1, {{"movable_id", "ui2"}, {"event", "ui2"}, {"ts", "ui8"}, {"is_native_coord", "ui1"}, {"x","f4"}, {"y", "f4"}, {"z", "f4"}, {"vx","f4"}, {"vy", "f4"}, {"vz", "f4"}}, function(args) 
                                            end 
                                        },
                                    },
    DURATION_REPORTER =            {name="DurationReporter",           act_type=10, params={"event"}, optional={},
                                        rpc_handler = {2, {{"event", "ui2"}, {"duration", "ui8"} }, function() end},
                                    },
    DIGITAL_SIGNAL_VALUE_SETTER =  {name="DigitalSignalValueSetter",   act_type=11, params={"signal", "value"}, optional={}},
    ANALOG_SIGNAL_VALUE_SETTER =   {name="AnalogSignalValueSetter",    act_type=12, params={"signal", "value"}, optional={}},
    SYNCER =                       {name="Syncer",                     act_type=13, params={}, optional={}},
    ANALOG_SIGNAL_VALUE_REPORTER=  {name="AnalogSignalValueReporter",  act_type=14, params={"signal", "event"}, optional={},
                                        rpc_handler =     {35, {{"ts", "ui8"}, {"event", "ui2"}, {"signal_id", "ui2"}, {"value", "f4"}}, function() end},
                                    },
    DIGITAL_SIGNAL_VALUE_REPORTER= {name="DigitalSignalValueReporter", act_type=15, params={"signal", "event"}, optional={},
                                        rpc_handler =     {41, {{"ts", "ui8"}, {"event", "ui2"}, {"signal_id", "ui2"}, {"value", "ui1"}}, function() end},
                                    },
    HW_MODULE_CONTROLLER=          {name="GenericHWModuleController",  act_type=16, params={"module", "state"}, optional={}},
    MOVE_LIMITS_SETTER  =          {name="MoveLimitsSetter",           act_type=17, params={"movable", "x_min", "y_min", "z_min", "x_max", "y_max", "z_max"}, optional={"x_min", "y_min", "z_min", "x_max", "y_max", "z_max"}},
    VALUE_DIFFERENCE_WAITER  =     {name="ValueDifferenceWaiter",      act_type=18, params={"source1", "source1_type", "source2", "source2_type", "threshold", "compare_type", "time_hysteresis"}, optional={}, LESSER=0, GREATER=1, PARAMETER=0, SIGNAL=1},
    POSITION_DETECTOR  =           {name="PositionDetector",           act_type=19, params={"movable", "x", "y", "z", "threshold", "op_type"}, optional={ "x", "y", "z"}, WHEN_GREATER=0, WHEN_LESSER=1},
    PARAM_NON_ZERO_WAITER  =       {name="ParamNonZeroWaiter",       act_type=20, params={"source", "time_hysteresis"}, optional={"time_hysteresis"}},
    PARAMETER_VALUES_SENDER    =   {name="ParameterValuesSender",      act_type=21, params={"event", "param1", "param2", "param3", "param4", "param5", "param6", "param7", "param8", "param9", "param10"}, optional={ "param1", "param2", "param3", "param4", "param5", "param6", "param7", "param8", "param9", "param10"},
                                        rpc_handler = {51, {{"ts", "ui8"}, {"event", "ui2"}, {"param1", "f4"}, {"param2", "f4"}, {"param3", "f4"}, {"param4", "f4"}, {"param5", "f4"}, {"param6", "f4"}, {"param7", "f4"}, {"param8", "f4"}, {"param9", "f4"}, {"param10", "f4"}}, function(args) 
                                            
                                        end
                                        },},
    MOVEMENT2 =                     {name="Movement2",                   act_type=22,  params={"movable", "is_relative", "x", "y", "z", "vx", "vy", "vz", "ax", "ay", "az", "jerk_limit", "accel_limit", "drift_limit", "speed_limit", "max_dynamic_error", "max_endpoint_error", "T"}, optional={"x", "y", "z", "vx", "vy", "vz", "ax", "ay", "az", "max_dynamic_error", "max_endpoint_error", "T", "jerk_limit"}},
    CONST_SPEED_MOVEMENT =          {name="ConstSpeedMovement",       act_type=23,  params={"movable", "is_relative", "px", "py", "pz", "speed_mag", "max_dynamic_error", "max_endpoint_error", "T"}, optional={"px", "py", "pz", "max_dynamic_error", "max_endpoint_error", "T", "speed_mag"}},
    PARAMETRIC_MOVEMENT =           {name="ParametricMovement",        act_type=24,  params={"movable", "p", "px", "py", "pz", "time_param", "max_dynamic_error", "T"}, optional={"T","p", "px", "py", "pz"}},
    HAL_REQUEST =                   {name="HALRequest",               act_type=25,  params={"requestType", "message"}, optional={}},
    CONST_ACCELERATION_MOVEMENT =   {name="ConstAccelerationMovement", act_type=26,  params={"movable", "is_relative", "x", "y", "z", "acceleration", "deceleration", "max_speed", "max_dynamic_error", "max_endpoint_error"}, optional={"x", "y", "z", "deceleration", "max_speed", "max_dynamic_error", "max_endpoint_error"}},

} end


function string.tohex(str)
    return (str:gsub('.', function (c)
        return string.format('%02X', string.byte(c))
    end))
end



mc.errorsTable = {}
mc.errorsTable[    0   ]=  "N_A"
mc.errorsTable[    1   ]=  "NO_ERROR"
mc.errorsTable[    2   ]=  "NO_FREE_ACTION_NODES"
mc.errorsTable[    3   ]=  "ACTION_NOT_UNIQUE"
mc.errorsTable[    4   ]=  "NO_FREE_CONNECTIONS"
mc.errorsTable[    5   ]=  "MOVABLE_NOT_FOUND"
mc.errorsTable[    6   ]=  "CALIBRATABLE_NOT_FOUND"
mc.errorsTable[    7   ]=  "CONNECTION_SRC_NODE_NOT_FOUND"
mc.errorsTable[    8   ]=  "CONNECTION_TRG_NODE_NOT_FOUND"
mc.errorsTable[    9   ]=  "START_NODE_NOT_FOUND"
mc.errorsTable[    10  ]=  "GRAPH_VALIDATION_FAILED"
mc.errorsTable[    11  ]=  "NODE_TO_REMOVE_NOT_FOUND"
mc.errorsTable[    12  ]=  "SMOOTH_MOVEMENT_CALCULATION_FAILED"
mc.errorsTable[    13  ]=  "NOT_IMPLEMENTED"
mc.errorsTable[    14  ]=  "MOVABLE_BUSY"
mc.errorsTable[    15  ]=  "ACTION_REQUIRED_PARAMETERS_NOT_FOUND"
mc.errorsTable[    16  ]=  "ACTION_REQUIRED_PARAMETERS_NOT_SET"
mc.errorsTable[    17  ]=  "PARAMETER_LOCKED"
mc.errorsTable[    18  ]=  "PARAMETER_INDEX_OUT_OF_RANGE"
mc.errorsTable[    19  ]=  "PARAMETER_SET_WRONG_TYPE_OR_DATA"
mc.errorsTable[    20  ]=  "SMOOTH_MOVEMENT_WRONG_START_POS_HINT"
mc.errorsTable[    21  ]=  "PARAMETER_OCCUPIED"
mc.errorsTable[    22  ]=  "MOVABLE_COORD_UNREACHABLE"
mc.errorsTable[    23  ]=  "MOVABLE_BAD_DYNAMIC"
mc.errorsTable[    24  ]=  "BAD_CMD_GRAPH_STATE"
mc.errorsTable[    25  ]=  "PERSISTENT_MEMORY_HAL_ERROR"
mc.errorsTable[    26  ]=  "HARDWARE_MODULE_BUSY"
mc.errorsTable[    27  ]=  "UNKNOWN_HARDWARE_TYPE"
mc.errorsTable[    28  ]=  "WRONG_HARDWARE_MODULE_CONTRUCTOR_PARAMS"
mc.errorsTable[    29  ]=  "HARDWARE_MODULE_REQUIRED_PARAMETERS_NOT_SET"
mc.errorsTable[    30  ]=  "HARDWARE_MODULE_ID_OUT_OF_RANGE"
mc.errorsTable[    31  ]=  "WRONG_ACTION_CONTRUCTOR_PARAMS"
mc.errorsTable[    32  ]=  "ANALOG_SIGNAL_NOT_FOUND"
mc.errorsTable[    33  ]=  "DIGITAL_SIGNAL_NOT_FOUND"
mc.errorsTable[    34  ]=  "SIGNAL_BUSY"
mc.errorsTable[    35  ]=  "UNKNOWN_ACTION"
mc.errorsTable[    36  ]=  "SERIAL_SENDING_ERROR"
mc.errorsTable[    37  ] = "HARDWARE_MODULE_NOT_RUNNING"
mc.errorsTable[    38  ] = "HARDWARE_MODULE_NOT_FOUND"
mc.errorsTable[    39  ] = "MOVEMENT_BAD_END_POS_PRECISION"
mc.errorsTable[    40  ] = "MOVABLE_OUT_OF_LIMITS"
mc.errorsTable[    41  ] = "START_NODE_NOT_SET"
mc.errorsTable[    42  ] = "MOVABLE_COORD_DYNAMICALLY_UNREACHABLE"
mc.errorsTable[    43  ] = "HAL_RPC_REQUEST_FAILED"
mc.errorsTable[    44  ] = "SMOOTH_MOVEMENT_CALCULATION_FAILED_DRIFT_LIMIT"
mc.errorsTable[    45  ] = "SMOOTH_MOVEMENT_CALCULATION_FAILED_SPEED_ACCEL_LIMIT"
mc.errorsTable[    46  ] = "HAL_CALL_ERROR"




function mc.parseActionClassesRPCEndpoints(actionClasses)
    local ret = {}

    for className, actionWithHandlerClass in pairs(actionClasses) do
        if actionWithHandlerClass.rpc_handler ~= nil  then
            actionWithHandlerClass.callbacks = {}
            local h = actionWithHandlerClass.rpc_handler
            
            local args = h[2]

            local sig = string.char(h[1])
            local args_p = {}
            local args_data_length = 0
            for _, arg_data in ipairs(args) do
                local arg_name, arg_type = arg_data[1], arg_data[2]

                local arg_bin_size = binaryRPCargumentByteLength(arg_type)
                args_data_length = args_data_length + arg_bin_size
                table.insert(args_p, {name=arg_name, parser=function(data) 
                    return parseBinaryRPCargument(data, arg_type), arg_bin_size
                end})
            end
            args_data_length = args_data_length + 1
            local t = {}
            t.args_parsers = args_p
            t.data_length = args_data_length
            t.handler = function(args)
                (h[3])(args)
                if actionWithHandlerClass.callbacks[args["event"]] == nil then return end
                for clb, _ in pairs(actionWithHandlerClass.callbacks[args["event"]]) do
                    clb(args)
                end
            end
            if ret[sig] == nil then  ret[sig] = {} end
            table.insert(ret[sig], t)
        end
    end
    return ret
end

function mc.actionGraphError(self, message)
    local ID = "n/a"
    if self ~= nil then ID = self.ID end
    local errTxt = '<'..ID..'> ' .. message.."\n"
    for i=2,20 do
        local info = debug.getinfo(i)
        if info == nil then break end

        local n = info.name or "n/a"
        local src = info.source or "n/a"
        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
        local line = info.currentline or "n/a"
        errTxt = errTxt .. "\t" .. src .. "," .. line .. ": " .. n .. "\n"
    end
    utils.logError("[" .. utils.date_string()
    .. "] "..errTxt)
    error("[" .. utils.date_string()
						  .. "] "..errTxt)
end

function mc:robotInteractionError(message)
    self:Disconnect()

    local errTxt = '<'..self.ID..'> ' .. message.."\n"
    for i=2,10 do
        local info = debug.getinfo(i)
        if info == nil then break end

        local n = info.name or "n/a"
        local src = info.source or "n/a"
        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
        local line = info.currentline or "n/a"
        errTxt = errTxt .. "\t" .. src .. "," .. line .. ": " .. n .. "\n"
    end
    utils.print("[" .. utils.date_string()
    .. "] "..errTxt)

   utils.logError("[" .. utils.date_string()
    .. "] "..errTxt)
    return false
end

function mc.RPCHandler(dispatch_table)
    return actiongraph_rpc_proto.RPC(dispatch_table, {})
end

mc.outputRPC = actiongraph_rpc_proto.RPC({}, mc.rpc_senders)

function mc.send_rpc(self, sendFunc, name, values)
    local res, err = mc.outputRPC.send(sendFunc, name, values)
    if res == false then
        return mc.actionGraphError(self, err)
    end
end

function mc:SendEvent(waiter_action)
    self:send_rpc(self.serialSender, "EVENT", {event_id=waiter_action.params.event.value})
end

function mc:FindActionByID(id)
    return self.actions_by_ID[id]
end

function mc:FindHWModuleByID(id)
    return self.hw_modules_by_ID[id]
end


function mc:StartGraph()
    
    local received = false
    local addResult = {}
    local event = scheduler.NewEvent()
    self.cmdGraphStartResponseHook = function(args)
        addResult = args
        received = true
        event:set()
    end
    self:send_rpc(self.serialSender, "START_CMD_GRAPH", {})
    local success = scheduler.waitEventWithTimeout(event, 5)
    if received ~= true or addResult.error ~= 1 then
        utils.print(addResult.error)
        if received == true then
            return self:robotInteractionError("Failed to start cmd graph, error: "..mc.errorsTable[addResult.error])
        else
            return self:robotInteractionError("Failed to start cmd graph, answer timeout")
        end
    end

    return true
end

function mc:GetStateHash()
    local received = false
    local addResult = {}
    local event = scheduler.NewEvent()
    self.stateHashResponseHook = function(args)
        addResult = args
        event:set()
    end
    self:send_rpc(self.serialSender, "GRAPH_STATE_HASH", {})
    local success = scheduler.waitEventWithTimeout(event, 5)

    return addResult
end

function mc:RebootToBootloader()
    self:send_rpc(self.serialSender, "REBOOT_TO_BOOTLOADER", {})
end

function mc:StopHardwareModules()
    local params = {}
    local event = scheduler.NewEvent()
    self.hardwareStopResponseHook = function(args)
        params = args
        event:set()
    end

    self:send_rpc(self.serialSender, "STOP_HARDWARE", {})
    local success = scheduler.waitEventWithTimeout(event, 5)

    if params.error ~= 1 then utils.print(mc.errorsTable[params["error"]]) end
    return params.error == 1

end

function mc:ResetRobotState()
    local received = false
    local event = scheduler.NewEvent()
    self.cmdGraphClearResponseHook = function(args)
        received = true
        event:set()
    end
    self:send_rpc(self.serialSender, "CLEAR", {})

    local success = scheduler.waitEventWithTimeout(event, 5)
    if received ~= true then self:robotInteractionError("Cannot reset robot state") end
end


function mc:UniqueEventID()
    local ret = self.next_unique_event_id
    self.next_unique_event_id = self.next_unique_event_id + 1
    return ret
end

function mc:UniqueHardwareID()
    local ret = self.next_unique_hw_id
    self.next_unique_hw_id = self.next_unique_hw_id + 1
    return ret
end


function mc:calculateCurrentStateHash()
    local dataToHash = ""

    local param_keys1 = {}
    for i, p in ipairs(self.paramsStateHashes) do param_keys1[p.id] = i end
    local param_keys2 = {}
    for k in pairs(param_keys1) do table.insert(param_keys2, k) end
    table.sort(param_keys2)
    for _, k in ipairs(param_keys2) do 
        dataToHash = dataToHash .. self.paramsStateHashes[param_keys1[k]].hashData
    end

    dataToHash = dataToHash .. serialiseBinaryRPCargument(self.preparedEntryNode.id, "ui4")

    for _, p in ipairs(self.actionsToUpload) do
        dataToHash = dataToHash .. p.hashData
    end

    for _, p in ipairs(self.connectionsToUpload) do
        dataToHash = dataToHash .. p.hashData
    end


    local hw_keys1 = {}
    for i, p in ipairs(self.hardwareToUpload) do hw_keys1[p.rpc_params.id] = i end
    local hw_keys2 = {}
    for k in pairs(hw_keys1) do table.insert(hw_keys2, k) end
    table.sort(hw_keys2)
    for _, k in ipairs(hw_keys2) do 
        dataToHash = dataToHash .. self.hardwareToUpload[hw_keys1[k]].hashData
    end

    return memory64bitHash(dataToHash)
end

function mc:ByteCodeStats()
    local res = OrderedTable()
    res.stateHash = self:calculateCurrentStateHash():tohex()
    res.actions_count = #self.actionsToUpload
    res.connections_count = #self.connectionsToUpload
    res.parameters_count = #self.paramsToUpload
    res.hw_modules_count = #self.hardwareToUpload
    res.startup_node_set =  self.preparedEntryNode ~= nil
    return res
end

function mc:UploadAndStart(verbous)
    local verbous = verbous or false

    if self.preparedEntryNode == nil then
        return self:actionGraphError("Set entry node")
    end
    local currentStateHash = self:calculateCurrentStateHash()

    local stateInfo = self:GetStateHash()
    if stateInfo.error ~= 1 then
        return self:robotInteractionError("cannot retrieve state hash")
    end
    if stateInfo.state_hash == currentStateHash then
       utils.info(5, "Actiongraph program is already uploaded, continuing")
       return true
    end

    utils.print("Current graph is different from graph requested for uploading, overwriting")
    do
        local received = false
        local event = scheduler.NewEvent()
        self.cmdGraphClearResponseHook = function(args)
            received = true
            event:set()
        end
        self:send_rpc(self.serialSender, "CLEAR", {})

        local success = scheduler.waitEventWithTimeout(event, 5)
        if not received then
            self:robotInteractionError("Cannot clear current graph")
        end
    end
    local addResult = {}
    local event = scheduler.NewEvent()
    self.setEntryResponseHook = function(args)
        addResult = args
        event:set()
    end
    self:send_rpc(self.serialSender, "SET_CMD_GRAPH_ENTRY", {entry_node=self.preparedEntryNode.id})
    local success = scheduler.waitEventWithTimeout(event, 5)
    if addResult.error ~= 1 or addResult.action_id ~= self.preparedEntryNode.id then 
        return self:robotInteractionError("Failed to set entry, error: "..mc.errorsTable[addResult.error])
    end

    if #self.paramsToUpload > 0 then
        if verbous then 
            utils.print(string.format( "uploading %d params...",#self.paramsToUpload ))
        end
        for _, p in ipairs(self.paramsToUpload) do
            local addResult = {}
            local received = false
            if self.paramSetResponseHooks[p.rpc_params.param_id] == nil then
                self.paramSetResponseHooks[p.rpc_params.param_id] = {}
            end            
            local event = scheduler.NewEvent()
            local h = function(args)
                if args.param_id == p.rpc_params.param_id then
                    addResult = args
                    received = true
                    event:set()
                end
            end
            self.paramSetResponseHooks[p.rpc_params.param_id][h] = true
            self:send_rpc(self.serialSender, p.rpc_id, p.rpc_params)
           
            local success = scheduler.waitEventWithTimeout(event, 5)
            self.paramSetResponseHooks[p.rpc_params.param_id][h] = nil
            if received == true then
                if addResult.error ~= 1 then
                    -- TODO print param
                    return self:robotInteractionError("Param set failed: "..mc.errorsTable[addResult.error])
                end
            else
                return self:robotInteractionError("Param set failed: timeout")
            end
        end
        if verbous then
            utils.print("done.")
        end
    end


    if #self.hardwareToUpload > 0 then
        if verbous then 
            utils.print(string.format( "initialising %d hardware modules...",#self.hardwareToUpload ))
        end
        for _, p in ipairs(self.hardwareToUpload) do
            local addResult = {}
            local received = false
            local event = scheduler.NewEvent()
            self.hardwareSetResponseHook = function(args)
                addResult = args
                received = true
                event:set()
            end
            self:send_rpc(self.serialSender, p.rpc_id, p.rpc_params)
          
            local success = scheduler.waitEventWithTimeout(event, 5)
            if received == true then
                if addResult.error ~= 1 then 
                    local hw = self:FindHWModuleByID(addResult.id)
                    if hw and hw.alias then
                        return self:robotInteractionError(string.format( "Hardware module '%s' set failed with error: %s", hw.alias ,mc.errorsTable[addResult.error] ))
                    else
                        return self:robotInteractionError(string.format( "Hardware module id=%d, type=%d set failed with error: %s", addResult.id, addResult.hw_type,mc.errorsTable[addResult.error] ))
                    end
                end
            else
                return self:robotInteractionError(string.format( "Hardware module set failed with error: timeout" ))
            end
        end
        if verbous then 
            utils.print("done.")
        end
    end


    if #self.actionsToUpload > 0 then
        if verbous then
            utils.print(string.format( "uploading %d actions...",#self.actionsToUpload ))
        end
        for _, p in ipairs(self.actionsToUpload) do
            local addResult = {}
            local received = false
            local event = scheduler.NewEvent()
            self.actionCreateResponseHook = function(args)
                addResult = args
                received = true
                event:set()
            end
            self:send_rpc(self.serialSender, p.rpc_id, p.rpc_params)

            local success = scheduler.waitEventWithTimeout(event, 5)
            if addResult.action_error == 1 and addResult.action_id == p.rpc_params.id and addResult.add_error == 1 then 
                -- utils.print("Action ", self:FindActionByID(addResult.action_id).alias, p.rpc_params.id)
            else
                if received == true then
                    if addResult.action_error ~= 1 and addResult.action_error ~= 0 then 
                        return self:robotInteractionError("New action error: " .. mc.errorsTable[addResult.action_error])
                    end
                    if addResult.add_error ~= 1 then 
                        return self:robotInteractionError(string.format( "Action '%s' adding error: %s" , self:FindActionByID(addResult.action_id).alias, mc.errorsTable[addResult.add_error]))
                    end
                    -- return false
                else
                    return self:robotInteractionError(string.format( "Action '%s' adding error: timeout" , self:FindActionByID(p.rpc_params.id).alias))
                end
            end
        end
        if verbous then 
            utils.print("done.")
        end
    end

    if #self.connectionsToUpload > 0 then
        if verbous then 
            utils.print(string.format( "uploading %d connections...",#self.connectionsToUpload ))
        end

        for _, p in ipairs(self.connectionsToUpload) do
            local addResult = {}
            local received = false
            local event = scheduler.NewEvent()
            self.connectionCreateResponseHook = function(args)
                addResult = args 
                received = true
                event:set()
            end
            self:send_rpc(self.serialSender, p.rpc_id, p.rpc_params)

            local success = scheduler.waitEventWithTimeout(event, 5)
            if received == false then 
                return self:robotInteractionError("Failed added connection: timeout")
            elseif addResult.error ~= 1 or addResult.src_action_id ~= p.c.source or addResult.trg_action_id ~= p.c.target then
                local es = ""
                for k, v in pairs(p.c) do
                    es = es .. k.."="..v.." "
                    utils.print("\t", k, ":", v)
                end
                return self:robotInteractionError("Failed added connection: "..mc.errorsTable[addResult.error]..": "..es)
            end
        end
        if verbous then 
            utils.print("done.")
        end
    end
    utils.print("uploading done, saving to permanent storage...")
    self:SaveState()

    utils.print("checking program integrity...")
    local stateInfo = self:GetStateHash()
    if stateInfo.error ~= 1 then
        return self:robotInteractionError("cannot retrieve logic state hash")
    end
    if stateInfo.state_hash ~= currentStateHash then
        return self:robotInteractionError("integrity check failed")
    end
    utils.print("done")



    utils.print("starting the graph...")
    self:StartGraph()
    utils.print("done")
    return true
end

function mc:getHardwareList()
    local toSend = {}
    for i, m in ipairs(self.hardwareToUpload) do
        table.insert(toSend, {id = m.moduleID, class = m.moduleClassName, initParams = m.paramDefaultValues})
    end
    return toSend
end

function mc:Action(action_class, ...)
    local id = self.next_action_id
    self.next_action_id = self.next_action_id + 1

    local info = debug.getinfo(2)
    if info == nil then info = debug.getinfo(1) end
    local n = info.name or "n/a"
    local src = info.source or "n/a"
    if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
    local line = info.currentline or "n/a"
    local alias = "ACTION "..id.. " at " .. src .. ":" .. line
    


    if action_class == nil or type(action_class) ~= "table" then
        return self:actionGraphError("unknown action")
    end
    local params = {}


    for _, in_param_group in ipairs({...}) do
        if type(in_param_group) == "table" then 
            for _k, _v in pairs(in_param_group) do
                if type(_v) ~= "table" or _v.id == nil then
                    return self:actionGraphError("Pass correct params to Action")
                end
                params[_k] = _v
            end
        end
    end

    
    local opt_dict = {}
    if type(action_class.optional) == "table" then
        for _, n in ipairs(action_class.optional) do 
            opt_dict[n] = true
        end
    end

    for _, n in ipairs(action_class.params) do 
        if opt_dict[n] == true and params[n] == nil then

            params[n] = self:ParamUnset()
        end
        if params[n] == nil  then 
            return self:actionGraphError("Missing param "..n)
        end
    end

    local params_serialised = ""
    for _, n in ipairs(action_class.params) do
        params_serialised = params_serialised..serialiseBinaryRPCargument(params[n].id, "ui2")
    end
    
    local hashData = ""
    hashData = hashData .. serialiseBinaryRPCargument(action_class.act_type+1, "ui1")
    hashData = hashData .. params_serialised

    
    table.insert(self.actionsToUpload, {rpc_id="ADD_ACTION", rpc_params={id=id, act_type=action_class.act_type, param_count=#action_class.params, param_ids=params_serialised}, hashData=hashData})
    local ret = {id=id, alias=alias, params=params, action_type_name=action_class.name, action_class = action_class}

    ret.WithErrorCallback = function(callback) 
        if self.actionErrorCallbacks[ret.id] == nil then
            self.actionErrorCallbacks[ret.id] = {}
        end
        table.insert(self.actionErrorCallbacks[ret.id], callback)
        return ret
    end
    
    if action_class.rpc_handler ~= nil then
        ret.WithEventCallback = function(callback) 
            if action_class.callbacks[ ret.params.event.value] == nil then
                action_class.callbacks[ret.params.event.value] = {}
            end
            action_class.callbacks[ret.params.event.value][callback] = true

            return ret
        end

        ret.WaitForEvent = function(timeout)
            local rcv = false
            local event = scheduler.NewEvent()
            local clb = function () 
                rcv = true
                event:set()
            end
            if action_class.callbacks[ ret.params.event.value] == nil then
                action_class.callbacks[ret.params.event.value] = {}
            end
            action_class.callbacks[ret.params.event.value][clb] = true

            local success = scheduler.waitEventWithTimeout(event, timeout/1000)
            action_class.callbacks[ret.params.event.value][clb] = nil
            return rcv

        end
    else
        ret.WithEventCallback = function() self:actionGraphError("Action type "..ret.action_type_name.." doesn't provide callbacks") end
        ret.WaitForEvent = function() self:actionGraphError("Action type "..ret.action_type_name.." doesn't provide callbacks") end
    end
    self.actions_by_ID[id] = ret

    ret.WithAlias = function (al, replace)
        if replace then
            ret.alias = al
        else
            ret.alias = al.."("..ret.alias..")"
        end
        return ret
    end
    return ret
end

function mc:parseConditions(isAll, ...)
    local preparedConnections = {}
    for _, group in ipairs({...}) do
        for _, c in ipairs(group) do
            table.insert(preparedConnections, c)
        end
    end

    local conjIndex = -1
    if #preparedConnections == 0 then
        return self:actionGraphError("Should be at least 1 source action for connections")
    end
    if isAll == true and #preparedConnections > 1 then
        conjIndex = self.conj_group_index
        self.conj_group_index = self.conj_group_index + 1
    end
    
    for _, c in ipairs(preparedConnections) do
        c.conjunctionGroupID = conjIndex
    end
    return preparedConnections
end

function mc:When(...)
    return self:whenInternal(true, ...)
end

function mc:WhenAnyOf(...)
    return self:whenInternal(false, ...)
end

function mc:whenInternal(isAll, ...)
    local preparedConnections = self:parseConditions(isAll, ...)
  
    local preparedConnectionsObj = {}

    function preparedConnectionsObj.Do(...)
        local targets = {}

        for _, group in ipairs({...}) do
            for _, c in ipairs(group) do
                table.insert(targets, c)
            end
        end

        if #preparedConnectionsObj.preparedConnections == 0 or #targets == 0 then 
            return self:actionGraphError("Should be at least 1 target action and 1 When condition")
        end

        local to_upload = {}

        if      #preparedConnectionsObj.preparedConnections == 1 and #targets >= 1 then
            local src = preparedConnectionsObj.preparedConnections[1]
            for _, trg in ipairs(targets) do                
                table.insert(to_upload, {
                    when=src.when,
                    source=src.source,
                    task=trg.task,
                    target=trg.target,
                    conjunctionGroupID=src.conjunctionGroupID
                })
            end
        elseif  #targets == 1 and #preparedConnectionsObj.preparedConnections >= 1 then
            local trg = targets[1]
            for _, src in ipairs(preparedConnectionsObj.preparedConnections) do
                table.insert(to_upload, {
                    when=src.when,
                    source=src.source,
                    task=trg.task,
                    target=trg.target,
                    conjunctionGroupID=src.conjunctionGroupID
                })
            end

        else
            local proxyAction = self:Action(self.actionClasses.SYNCER)
            table.insert(to_upload, {
                when=0,
                source=proxyAction.id,
                task=1,
                target=proxyAction.id,
                conjunctionGroupID=-1
            })
            for _, src in ipairs(preparedConnectionsObj.preparedConnections) do
                table.insert(to_upload, {
                    when=src.when,
                    source=src.source,
                    task=0,
                    target=proxyAction.id,
                    conjunctionGroupID=src.conjunctionGroupID
                })
            end

            for _, trg in ipairs(targets) do                
                table.insert(to_upload, {
                    when=1,
                    source=proxyAction.id,
                    task=trg.task,
                    target=trg.target,
                    conjunctionGroupID=-1
                })
            end

        end

        for i, c in ipairs(to_upload) do
            local hashData = ""
            hashData = hashData .. serialiseBinaryRPCargument(c.target, "ui4")
            hashData = hashData .. serialiseBinaryRPCargument(c.source, "ui4")
            if c.conjunctionGroupID ~= -1 then
                hashData = hashData .. serialiseBinaryRPCargument(c.conjunctionGroupID, "ui4")
            end
            hashData = hashData .. serialiseBinaryRPCargument(c.task, "ui4")
            hashData = hashData .. serialiseBinaryRPCargument(c.when, "ui4")
            table.insert(self.connectionsToUpload, {rpc_id="ADD_CONNECTION", rpc_params=c, c=c, hashData=hashData})
        
        end

    end
  
    preparedConnectionsObj.preparedConnections = preparedConnections
    return preparedConnectionsObj
end

function mc:Started(...)
    local preparedConnections = {}
    for _, action_obj in ipairs({...}) do
        if action_obj == nil or action_obj.id == nil then 
            return self:actionGraphError("Pass action object here") 
        end
        table.insert(preparedConnections, {
            source=action_obj.id,
            when=0
        })
    end
    return preparedConnections
end

function mc:Stopped(...)
    local preparedConnections = {}
    local in_acts = {...}
    if #in_acts == 0 then
        return self:actionGraphError("Pass action objects here")
    end
    for _, action_obj in ipairs(in_acts) do
        if action_obj == nil or action_obj.id == nil then 
            return self:actionGraphError("Pass action object here")
        end
        table.insert(preparedConnections, {
            source=action_obj.id,
            when=1
        })
    end
    return preparedConnections
end

function mc:Erred(...)
    local preparedConnections = {}
    local in_acts = {...}
    if #in_acts == 0 then
        return self:actionGraphError("Pass action objects here")
    end
    for _, action_obj in ipairs(in_acts) do
        if action_obj == nil or action_obj.id == nil then 
            return self:actionGraphError("Pass action object here") 
        end
        table.insert(preparedConnections, {
            source=action_obj.id,
            when=2
        })
    end
    return preparedConnections
end

function mc:Start(...)
    local preparedConnections = {}
    local in_acts = {...}
    if #in_acts == 0 then
        return self:actionGraphError("Pass action objects here")
    end
    for _, action_obj in ipairs(in_acts) do
        if action_obj == nil or action_obj.id == nil then return self:actionGraphError("Pass action object here") end
        table.insert(preparedConnections, {
            target=action_obj.id,
            task=0
        })
    end
    return preparedConnections
end

function mc:Stop(...)
    local preparedConnections = {}
    local in_acts = {...}
    if #in_acts == 0 then
        return self:actionGraphError("Pass action objects here")
    end
    for _, action_obj in ipairs(in_acts) do
        if action_obj == nil or action_obj.id == nil then return self:actionGraphError("Pass action object here") end
        table.insert(preparedConnections, {
            target=action_obj.id,
            task=1
        })
    end
    return preparedConnections
end

function mc:Cancel(...)
    local preparedConnections = {}
    for _, action_obj in ipairs({...}) do
        if action_obj == nil or action_obj.id == nil then return self:actionGraphError("Pass action object here") end
        table.insert(preparedConnections, {
            target=action_obj.id,
            task=2
        })
    end
    return preparedConnections
end


function mc:HALMessageListener(msgId, handler)
    if self.halDebugMessageListeners[msgId] == nil then
        self.halDebugMessageListeners[msgId] = {}
    end
    table.insert(self.halDebugMessageListeners[msgId], handler)
end

mc.paramTypeMappingForward = {
    f8=0,
    si8=1,
    vector=2,
    expression=3,
    bytestring=4
}

mc.paramTypeMappingBackward = {}
mc.paramTypeMappingBackward[0] = "f8"
mc.paramTypeMappingBackward[1] = "si8"
mc.paramTypeMappingBackward[2] = "vector"
mc.paramTypeMappingBackward[3] = "expression"
mc.paramTypeMappingBackward[4] = "bytestring"


function mc:Param(init_value, typeStr)
    local typeS = typeStr
    local id = self.next_param_id
    self.next_param_id = self.next_param_id + 1

    local info = debug.getinfo(3)
    if info == nil then info = debug.getinfo(2) end
    local n = info.name or "n/a"
    local src = info.source or "n/a"
    if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
    local line = info.currentline or "n/a"
    local alias = "PARAM "..id .. " at " .. src .. ":" .. line
    
    local ret = {id=id, alias=alias, typeS = typeS}
    local hashData = ""
    hashData = hashData .. serialiseBinaryRPCargument(id, "ui4")
    hashData = hashData .. serialiseBinaryRPCargument(mc.paramTypeMappingForward[typeS]+1, "ui1")
    if (typeS == "expression") then
        for _, tk in ipairs(init_value.tokens) do
            if tk[1] == "expr_token" then
                hashData = hashData .. serialiseBinaryRPCargument(tk[2], "ui1")
            elseif type(tk)=="table" and tk.id ~= nil and type(tk.id) == "number" then
                hashData = hashData .. serialiseBinaryRPCargument(tk.id, "ui2")
            else
                return self:actionGraphError("Bad token in expression parameter")
            end
        end
    end
    table.insert( self.paramsStateHashes, {id=id, hashData = hashData})
    function ret.Get() 
        local result = {}
        local received = false
    
        if self.paramValueResponseHooks[id] == nil then
            self.paramValueResponseHooks[id] = {}
        end
        local event = scheduler.NewEvent()
        local h = function(args) 
            result = args 
            received = true
            event:set()
        end

        self.paramValueResponseHooks[id][h] = true
    
        self:send_rpc(self.serialSender, "GET_PARAM", {param_id=id})
    
        local success = scheduler.waitEventWithTimeout(event, 5)

        self.paramValueResponseHooks[id][h] = nil
        if received == false then
            return nil
        end
        if result.param_id ~= id then
            self:actionGraphError("WRONG ID IN GET HANDLER")
        end
        if result["is_set"] ~= 1 then 
            ret.value = nil 
        else
            local param_type =  mc.paramTypeMappingBackward[result["type"]]

            if param_type == "f8" or param_type == "si8" then
                ret.value = parseBinaryRPCargument(result["data"], param_type)
            elseif param_type == "vector" then
                ret.value = Vector(
                    parseBinaryRPCargument(result["data"]:sub(1, 8), "f8"),
                    parseBinaryRPCargument(result["data"]:sub(9, 16), "f8"),
                    parseBinaryRPCargument(result["data"]:sub(17, 24), "f8")
                )
            elseif param_type == "bytestring" then
                ret.value = result["data"]:sub(2, 1 + string.byte(result["data"],1))
            else
                self:actionGraphError("Unknown param type")
            end
        end

        return ret.value
    end


    function ret.Set(value, upload_now) 
        if typeS == "expression" and type(value.value) == "string" and #value.value == mc.SerializedParameterByteLength then 
        elseif typeS == "vector" then

        elseif typeS == "bytestring" and type(value) == "string" then
        else
            if type(value) ~= "boolean" and type(value) ~= "number"  or value == nil then
                utils.print(string.format("Unsupported parameter value: '%s'", value))
                return
            end
        end
    
        if type(value) == "boolean" then
            if value == true then value = 1 else value = 0 end
        end
    

        local upload_rpc_cmd = {}
       
        local type_code = mc.paramTypeMappingForward[typeS]
        local d
        local s
        if typeS == "expression" then
            d = serialiseBinaryRPCargument(value.value, string.format("2a%s", mc.SerializedParameterByteLength))
            s = mc.SerializedParameterByteLength
        elseif typeS == "vector" then
            d = serialiseBinaryRPCargument(value.x, "f8")..serialiseBinaryRPCargument(value.y, "f8")..serialiseBinaryRPCargument(value.z, "f8")
            s = 24
        elseif typeS == "bytestring" then
            d = string.char(string.len(value))..value
            while #d < mc.SerializedParameterByteLength do
                d = d..string.char(0)
            end
            s = string.len(d)
        else
            d = serialiseBinaryRPCargument(value, typeS)
            s = binaryRPCargumentByteLength(typeS)
        end

        local c = {param_id=ret.id, set=1, type=type_code, size=s, data=d}
        upload_rpc_cmd = {rpc_id="SET_PARAM", rpc_params=c}
    
        if upload_now ~= "y" then
            
            local addResult = {}
            local received = false
            local event = scheduler.NewEvent()
            local h = function(args) 
                addResult = args 
                received = true
                event:set()
            end
            if self.paramSetResponseHooks[id] == nil then
                self.paramSetResponseHooks[id] = {}
            end

            self.paramSetResponseHooks[id][h] = true
            self:send_rpc(self.serialSender, upload_rpc_cmd.rpc_id, upload_rpc_cmd.rpc_params)
            local success = scheduler.waitEventWithTimeout(event, 5)

            self.paramSetResponseHooks[id][h] = nil
            if addResult.error ~= 1 then
                if addResult.error ~= nil then
                    utils.print("Param set failed: "..mc.errorsTable[addResult.error])
                else
                    utils.print("Param set failed: no answer")
                end
                return false
            end

            return true
        else
            table.insert(self.paramsToUpload, upload_rpc_cmd)
        end

        ret.value = value
    end
   
    ret.Set(init_value, "y") -- delayed
    self.params_by_ID[id] = ret
    return ret
end

function mc:ParamFloat(value)
    return self:Param(value, "f8")
end

function mc:ParamInt(value)
    return self:Param(value, "si8")
end

function mc:ParamVector(value_or_x, y, z)
    if y ~= nil and z ~= nil then
        value_or_x = Vector(value_or_x, y, z)
    end
    return self:Param(value_or_x, "vector")
end

function mc:ParamString(value)
    return self:Param(value, "bytestring")
end


mc.EXPR = {
    NOP = {"expr_token", 1},
    PLUS = {"expr_token", 2},
    MINUS = {"expr_token", 3},
    MULT = {"expr_token", 4},
    DIV = {"expr_token", 5},
    POW = {"expr_token", 6},
    SIN = {"expr_token", 7},
    COS = {"expr_token", 8},
    MOD = {"expr_token", 9},
    TIME_S = {"expr_token", 10},
    TIME_US = {"expr_token", 11},
    ROUND = {"expr_token", 12},
    IF = {"expr_token", 13},
    DIGITAL_SIG = {"expr_token", 14},
    ANALOG_SIG = {"expr_token", 15},
    NORM = {"expr_token", 16},
    SQ = {"expr_token", 17},
    SQRT = {"expr_token", 18},
    AND = {"expr_token", 19},
    OR = {"expr_token", 20},
    NOT = {"expr_token", 21},
    GREATER = {"expr_token", 22},
    LESSER = {"expr_token", 23},
    EQUAL = {"expr_token", 24},
    NORMALIZED = {"expr_token", 25},
    VECTOR = {"expr_token", 26},
    X = {"expr_token", 27},
    Y = {"expr_token", 28},
    Z = {"expr_token", 29},
    SETX = {"expr_token", 30},
    SETY = {"expr_token", 31},
    SETZ = {"expr_token", 32},
    UMINUS = {"expr_token", 33},
    UPLUS = {"expr_token", 34},
    NORMAL_NOISE = {"expr_token", 35},
    FORMAT_NUMBER = {"expr_token", 36},
    GETVAR = {"expr_token", 37},
    SETVAR = {"expr_token", 38},
}

function mc:ParamExpression(expr_tokens)

    local serialised_tokens = ""

    if #expr_tokens > mc.SerializedParameterByteLength/2 then return self:actionGraphError(string.format("Too many tokens in expression, should be %s max.", mc.SerializedParameterByteLength/2)) end
    for _, tk in ipairs(expr_tokens) do 
      
        local val
        if type(tk)=="table" and tk[1] == "expr_token" then
            val = tk[2] + 32768
        elseif type(tk)=="table" and tk.id ~= nil and type(tk.id) == "number" then
            val = tk.id
        else
            return self:actionGraphError("Bad token in expression parameter")
        end
        serialised_tokens = serialised_tokens..serialiseBinaryRPCargument(val, "ui2")
    end

    while #serialised_tokens < mc.SerializedParameterByteLength do
        serialised_tokens = serialised_tokens..serialiseBinaryRPCargument(mc.EXPR.NOP[2]+ 32768, "ui2")
    end


    return self:Param({value=serialised_tokens, tokens=expr_tokens}, "expression")
end


function mc:ParamUnset()
    local undefParam = {id=65535, value=nil, alias=nil}
    function undefParam.Set() return self:actionGraphError("Cannot set param of type 'Not set'") end
    function undefParam.Get() return self:actionGraphError("Cannot get param of type 'Not set'") end
    return undefParam
end

function mc:SaveState()
    local params = {}
    local event = scheduler.NewEvent()
    self.saveParamDBResponseHook = function(args)
        params = args
        event:set()
    end

    self:send_rpc(self.serialSender, "SAVE_STATE", {})
    self.ignoreHeartBeats = true
    local success = scheduler.waitEventWithTimeout(event, 5)
    self.prevHeartbeatReceived = millis()
    self.ignoreHeartBeats = false
    if params.error ~= 1 then 
        if params.error ~= nil then 
            self:robotInteractionError("SaveState error: "..mc.errorsTable[params["error"]])
        else
            self:robotInteractionError("SaveState error: answer timeout")
        end
    end
    return params.error == 1
end

function mc:SetGraphEntryNode(a)
    self.preparedEntryNode = a
end

--HardwareShortcuts
mc.hardwareClasses = {
    BASIC_PID_MOTOR_MOVABLE_HW_MODULE =                {name="BASIC_PID_MOTOR_MOVABLE_HW_MODULE", hw_type=0, params={"control_signal", "encoder_signal", "P", "I", "D", "resolution"}},
    DELTA_ROBOT_MOVABLE_HW_MODULE =                    {name="DELTA_ROBOT_KINEMATICS", hw_type=1, params={"forearm_l", "upperarm_l", "ljo", "ujo", "actuator0_id", "actuator1_id", "actuator2_id"}},
    DIGITAL_INPUT_SIGNAL_HW_MODULE =                   {name="DIGITAL_INPUT_SIGNAL", hw_type=2, params={"hal_id"}},
    DIGITAL_OUTPUT_SIGNAL_HW_MODULE =                  {name="DIGITAL_OUTPUT_SIGNAL", hw_type=3, params={"hal_id", "initialValue"}},
    ANALOG_INPUT_SIGNAL_HW_MODULE =                    {name="ANALOG_INPUT_SIGNAL", hw_type=4, params={"hal_id", "scale", "offset"}},
    ANALOG_OUTPUT_SIGNAL_HW_MODULE =                   {name="ANALOG_OUTPUT_SIGNAL", hw_type=5, params={"hal_id", "scale", "offset", "initialValue"}},
    LINEAR_ACTUATORS_DELTA_ROBOT_MOVABLE_HW_MODULE =   {name="LINEAR_ACTUATORS_DELTA_ROBOT_KINEMATICS", hw_type=6, params={"actuator_offset", "actuator_elevation", "forearm_l", "ljo", "actuator0_id", "actuator1_id", "actuator2_id"}},
    MOVABLE_COORD_SYSTEM_TRANSFORM_MOVABLE_HW_MODULE = {name="MOVABLE_COORD_SYSTEM_TRANSFORM_MOVABLE_HW_MODULE", hw_type=7, params={"movable", "translation_x", "translation_y", "translation_z", "rot_axis_x", "rot_axis_y", "rot_axis_z", "rot_angle", "scale_x", "scale_y", "scale_z", "speed_limit"}},
    FEED_FORWARD_MOTOR_MOVABLE_HW_MODULE =             {name="FEED_FORWARD_MOTOR_MOVABLE_HW_MODULE", hw_type=8, params={"speed_control_signal", "position_feedback_signal", "P", "I", "D", "resolution"}},
    MOVABLE_SIGNAL =                                   {name="MOVABLE_SIGNAL", hw_type=9, params={"signal0", "signal1", "signal2"}, optional={"signal1", "signal2"}},
    PERPENDICULAR_AXES_ROBOT =                         {name="PERPENDICULAR_AXES_ROBOT_KINEMATICS", hw_type=10, params={"actuator0", "actuator1", "actuator2"}, optional={"actuator0", "actuator1", "actuator2"}},
    DIGITAL_PULSES_GENERATOR =                         {name="DIGITAL_PULSES_GENERATOR", hw_type=11, params={"hal_id",  "frequency", "expression"}, optional={}},
    ANALOG_SIGNAL_GENERATOR =                          {name="ANALOG_SIGNAL_GENERATOR", hw_type=12, params={"hal_id",  "frequency", "expression"}, optional={}},
}

function mc:HardwareEntity(id, hw_class, startAfterLoading, ...)
    local params_groups = {...}
    local params = {}

    for _, t in ipairs(params_groups) do 
        for k, v in pairs(t) do
            if type(v) ~= "table" or v.id == nil then
                return self:actionGraphError("Pass correct params to HardwareEntity")
            end
            params[k] = v
        end
    end

    local opt_dict = {}
    if type(hw_class.optional) == "table" then
        for _, n in ipairs(hw_class.optional) do 
            opt_dict[n] = true
        end
    end

    for _, n in ipairs(hw_class.params) do 
        if opt_dict[n] == true and params[n] == nil then
            params[n] = self:ParamUnset()
        end
        if params[n] == nil then 
            return self:actionGraphError("Missing param "..n)
        end
    end

    local params_serialised = ""
    local paramDefaultValues = {}
    for _, n in ipairs(hw_class.params) do
        if params[n].id == nil then
            return self:actionGraphError("incorrect parameter in hardware initialisation")
        end
        if params[n].value ~= nil then 
            if type(params[n].value) == "number" then
                paramDefaultValues[n] = params[n].value 
            else
                paramDefaultValues[n] = "expression"
            end
        else
            paramDefaultValues[n] = "n/a"
        end
        params_serialised = params_serialised..serialiseBinaryRPCargument(params[n].id, "ui2")
    end
    local startN = 0
    if startAfterLoading then 
        startN = 1
    end
    local hashData = ""
    hashData = hashData .. serialiseBinaryRPCargument(id, "ui4")
    hashData = hashData .. serialiseBinaryRPCargument(hw_class.hw_type + 1, "ui1")
    hashData = hashData .. params_serialised
    table.insert(self.hardwareToUpload, {rpc_id="SET_HARDWARE_MODULE",
                                       rpc_params={id=id, hw_type=hw_class.hw_type, start_now = startN, param_count=#hw_class.params, param_ids=params_serialised},
                                       hashData = hashData,
                                       moduleClassName = hw_class.name,
                                       paramDefaultValues = paramDefaultValues,
                                       moduleID = id
                                        }
    )
    local ret = {id=id, params=params, name=hw_class.name}
    ret.WithAlias = function (al, replace)
        if replace then
            ret.alias = al
        else
            ret.alias = al.."("..ret.alias..")"
        end
        return ret
    end
    self.hw_modules_by_ID[id] = ret
    return ret
end

function mc:SendMessageToHal(id, data)
    self:send_rpc(self.serialSender, "HAL_DEBUG_MESSAGE", {id=id, size=#data, data=data})
end

function mc:HALRequest(requestType, data)
    utils.info(8, "HALRequest entered", requestType, data)
    self.halRequestLock:aquire()
    local event = scheduler.NewEvent()
    local res
    local h = function (r)
        res = r
        event:set()
    end
    self.halRequestResultHook = h
    self:send_rpc(self.serialSender, "HAL_REQUEST", {requestType=requestType, size=#data, data=data})
    scheduler.waitEventWithTimeout(event, 5)
  
    self.halRequestResultHook = nil
    self.halRequestLock:release()
    utils.info(8, "HALRequest exited", requestType, data)
    return res
end

function mc:FalseParam()
    if self.__falseParam == nil then
        self.__falseParam = self:ParamInt(false)
    end

    return self.__falseParam
end

function mc:TrueParam()
    if self.__trueParam == nil then
        self.__trueParam = self:ParamInt(true)
    end

    return self.__trueParam
end

function mc:FloatNullParam()
    if self.__floatNullParam == nil then
        self.__floatNullParam = self:ParamFloat(0)
    end

    return self.__floatNullParam
end



function mc:IsRobotReady()
    return self.isConnected and self.isReadyAndSynced
end


function mc:SetReadyCallback(f)
    table.insert(self.readyCallbacks, f)
end

function mc:SetDisconnectCallback(f)
    table.insert(self.diconnectedEventCallbacks, f)
end

function mc:Disconnect() 
    self.isReadyAndSynced = false
    self.isConnected = false
    self.currentSerialTransport:close()
    mc.robotSearchLock:aquire()
    mc.robotsConnectionPool[self.Serial] = nil
    mc.robotSearchLock:release()
    utils.info(10, "Called disconnect for robot with serial "..self.Serial)
    scheduler.sleep(0.050)
end

mc.robotSearchLock = scheduler.NewLock()

mc.robotsConnectionPool = {}

scheduler.addTask(function()
    while true do
        scheduler.sleep(0.100)
        mc.robotSearchLock:aquire()
        for robotSerial, entry in pairs(mc.robotsConnectionPool) do
            if millis() - entry.detectedAt > 3000 and entry.inUse ~= true then
                utils.info(10, "Removing connection from connection pool: ", robotSerial, entry.connString)
                mc.robotsConnectionPool[robotSerial].port:close()
                mc.robotsConnectionPool[robotSerial] = nil
                utils.info(10, "Removed connection from connection pool: ", robotSerial, entry.connString)
            end
        end
        mc.robotSearchLock:release()
    end
end, "robot connection pool task")

function mc.getAvailableConnections()
    local ret = {SerialTransport():availableSerialPorts("serialport2")}
    -- local ret = {
    --     "zmq in=tcp://127.0.0.1:10001 out=tcp://127.0.0.1:10000",
    --     "zmq in=tcp://127.0.0.1:10003 out=tcp://127.0.0.1:10002",
    --     "zmq in=tcp://127.0.0.1:10005 out=tcp://127.0.0.1:10004",
    --     "zmq in=tcp://127.0.0.1:10007 out=tcp://127.0.0.1:10006",
    --     "zmq in=tcp://127.0.0.1:10009 out=tcp://127.0.0.1:10008",
    --     "zmq in=tcp://127.0.0.1:10011 out=tcp://127.0.0.1:100010"
    -- }
    -- utils.print("Available connections: ", #ret)
    return ret
end

function mc.FindRobot(robotSerial, fixedTransport)
    utils.info(10, "FindRobot, aquiring lock")
    mc.robotSearchLock:aquire()
    utils.info(10, "FindRobot, done aquiring lock")
    if mc.robotsConnectionPool[robotSerial] == nil then
        utils.info(10, "Robot connection is not in connection pool: '"..robotSerial.. "'. Searching...")

        local connsToSearch = {}
        
        local tempConnsToSearch = {}
        if fixedTransport == nil then
            utils.info(10, "Manual transport config is not set, getting avaialble connections")
            tempConnsToSearch = mc.getAvailableConnections()
            utils.info(10, "Done getting available connections")
        else
            utils.info(10, "Using manual transport config: "..fixedTransport)
            tempConnsToSearch =  {fixedTransport}
        end
        for _, c in ipairs(tempConnsToSearch) do
            local usedBy
            local alreadyOpened
            for ser, e in pairs(mc.robotsConnectionPool) do
                if e.connString == c and e.inUse then
                    usedBy = ser
                    break
                elseif e.inUse == false then
                    alreadyOpened = true
                    break
                end
            end
            if usedBy ~= nil then
                utils.info(10, "Skipping connection ", c, " because it is used by '"..usedBy.."'")
            elseif alreadyOpened == true then
                utils.info(10, "Skipping connection ", c, " because already established")
            else
                table.insert(connsToSearch, c)
            end
        end
        
        if #connsToSearch == 0 then 
            mc.robotSearchLock:release()
            utils.info(10, "No available connections to search for robots")
            return nil
        end
        utils.info(10, "Starting searching for robots on available connections, opening transports")
        local searchDoneEvents = {}

        for i, config in ipairs(connsToSearch) do
            local doneEvent = scheduler.NewEvent()
            table.insert( searchDoneEvents, doneEvent)

            local port = SerialTransport()
            local status = false
            scheduler.addTask(function()
                local heartbeatH = function(args) 
                    if args.sw_major_version >= MINIMUM_REQUIRED_FW_MAJOR_VERSION then
                        utils.info(2, string.format("Robot '%s' is found on '%s'",  args.robot_unique_id, config))

                        status = true
                        local newCacheEntry = {
                            detectedAt = millis(),
                            port = port,
                            info = args,
                            connString = config,
                            inUse = false
                        }

                        mc.robotsConnectionPool[args.robot_unique_id] = newCacheEntry
                    else
                        utils.print("Skipped robot with incompatible FW", config)
                    end
                end
                local handler = mc.RPCHandler(actiongraph_rpc_proto.parseRPCEndpoints(
                    {
                        {28, { {"hw_major_version", "ui2"}, {"hw_minor_version", "ui2"}, {"sw_major_version", "ui2"}, {"sw_minor_version", "ui2"}, {"robot_unique_id", "2a8"}},  heartbeatH },
                    }
                ))
                if port:open(config) == true then
                    scheduler.sleep(0.50)
                    utils.info(10, string.format("Sending heartbeat request to '%s'", config))
                    local sf = function (data)
                        pcall(function ()
                            port:sendData(data)
                        end)
                    end
                    mc.send_rpc(nil, sf, "HEARTBEAT", {})

                    utils.info(10, string.format("Reading responses for heartbeat request from '%s'", config))
                    local ts = millis()
                    while millis() - ts < 1000 do
                        local ok, data = pcall(function() return port:readData(100) end)
                        if ok == true and data ~= nil then
                            handler.addRawData(data)
                            if status == true then
                                break
                            end
                        end
                    end
                    if status == false then
                        port:close()
                    end
                end
                doneEvent:set()
            end)
        end
        for _, doneEvent in ipairs(searchDoneEvents) do
            doneEvent:wait()
        end
    else
        utils.info(10, "Found in connection pool", robotSerial)
    end
    mc.robotSearchLock:release()
    
    if mc.robotsConnectionPool[robotSerial] == nil then
        utils.info(10, "Robot '", robotSerial, "' is not found")
        return nil
    end
    if mc.robotsConnectionPool[robotSerial].inUse == true then
        utils.print("Connection is already used", robotSerial)
        return nil
    end
    mc.robotsConnectionPool[robotSerial].inUse = true
    utils.info(10, "Connection to Robot '", robotSerial, "' is ready")
    return mc.robotsConnectionPool[robotSerial]
end

function mc:Connect()
    local lastMsgTs = 0
    local function printConnecting()
        if millis() - lastMsgTs > 2000 then
            utils.info(5, "Connecting to robot", self.ID, self.Serial, self.FixedTransport)
            lastMsgTs = millis()
        end
    end
    while self.isConnected == false do
        printConnecting()
        utils.info(10, "Attempt to find robot '", self.Serial, "'")
        
        local conn = mc.FindRobot(self.Serial, self.FixedTransport)
       
        if conn ~= nil then
            utils.info(10, "Attempt to find robot '", self.Serial, "' succeeded")
            self.isConnected = true
            self.currentSerialTransport = conn.port
            self.lastReceivedVersionInfo = utils.tableclone(conn.info)
            self.prevHeartbeatReceived = millis()
            self.currentConnection = conn.connString

            break
        else
            utils.info(10, "Attempt to find robot '", self.Serial, "' failed")
        end
        scheduler.sleep(0.500)
    end
end


function mc:MainCoroutine()
    while true do
        for _, h in ipairs(self.diconnectedEventCallbacks) do
            h()
        end
        while self:IsRobotReady() == false do
            self:Connect()
            if self.robotTransportReaderTask ~= nil then self.robotTransportReaderTask.cancel() end
            self.robotTransportReaderTask = scheduler.addTask(function ()
                while true do
                    local ts = millis()
                    local ok, new_data = pcall(function()return self.currentSerialTransport:readData()end)
                    if millis() - ts < 1 then
                        scheduler.sleep(0)
                    end
                    if ok ~= true then
                        if not new_data.tags or not new_data.tags[scheduler.TASK_CANCELLED] then
                            self:robotInteractionError("Transport read failure: "..tostring(new_data))
                        end
                        break
                    end
                    -- utils.print("ENTERED")
                    if new_data ~= nil then
                        for _, hhh in pairs(self.rpc_handlers) do
                            if hhh ~= nil then
                                hhh.addRawData(new_data)
                            end
                        end
                    end
                    -- utils.print("EXITED")
                end
            end)

            if self.ForceReupload == true then
                utils.print(string.format("Clearing robot '%s' state to do force graph reupload", self.ID))
                self:ResetRobotState()
               
            end
            if self:UploadAndStart(false) == true then
                self.isReadyAndSynced = true
                break
            end
        end

        for _, h in ipairs(self.readyCallbacks) do
            h()
        end
       
        while self:IsRobotReady() do
            self:send_rpc(self.serialSender, "HEARTBEAT", {})
            -- utils.print("@@@@@@@@@@@   HB SEND   @@@@@@@@@")
            if self.ignoreHeartBeats ~= true then
                if millis() - self.prevHeartbeatReceived > 2000  then 
                    utils.print("No heartbeats from robot", millis(), self.prevHeartbeatReceived)
                    
                    if self.robotTransportReaderTask ~= nil then self.robotTransportReaderTask.cancel() end
                    self.robotTransportReaderTask = nil
                    self:robotInteractionError("No heartbeats from robot")
                end
            else
                self.prevHeartbeatReceived = millis()
            end
            scheduler.sleep(0.5)
        end
    end
end

function mc:startTimingInstrumentation()
    self:HALMessageListener(100, function(data, size)
        if size < 12 then
            utils.print('Debug message (id = 100) does not have a large enough payload ')
            return
        end

        local minTime =  parseBinaryRPCargument(data:sub(1, 2), "ui2")
        local maxTime =  parseBinaryRPCargument(data:sub(3, 4), "ui2")
        local medTime =  parseBinaryRPCargument(data:sub(5, 6), "ui2")
        local avgTime =  parseBinaryRPCargument(data:sub(7, 8), "ui2")
        local tick =     parseBinaryRPCargument(data:sub(9, 12), "ui4")

        utils.print(string.format("Robot '%s' PERF: HAL Tick: %d; Tick timings (us): MIN: %d, MAX: %d, MED: %d, AVG: %d",
            self.id, tick, minTime, maxTime, medTime, avgTime))
    end)
    utils.print(string.format("'%s': ENABLING INSTRUMENTATION", self.ID))
    self:SendMessageToHal(100, "i")
end

return mc
