
local utils = require("utils")
local jsonschema = require 'jsonschema'
local scheduler = require"scheduler"


local path_lib = require"pl.path"
local actiongraph = actiongraph or {}

local graphPath = actiongraph.ContextGraphPath

local currentDir = path_lib.dirname(actiongraph.CurrentScriptPath)
local schema_validator = jsonschema.generate_validator(utils.parseYAMLFile(path_lib.join(currentDir, "..","api_spec","rpc_api_schema.yaml")))


local motor_count = 3


local function sendRPC(kind, args, session_id)
    local s = {
        robot_id = actiongraph.RobotID(),
        command = "user_custom_rpc",
        type = kind,
        args = args or {},
        session_id = session_id or ""
    }
    local ok, err = schema_validator(s)
    if ok == false then
        utils.print("Internal uC->PC RPC error:", err)
    else
        actiongraph.SendHostRPC(s)
    end
    
end

local function axis_graph_path(axis_index)
    return  graphPath..".".."a"..tostring(math.floor(axis_index)).."."
end

-- local movement_batch_locks = {}-- scheduler.NewLock()
local axis_states = {}

local function sendMvQueueState(axis_index, sender)
    sender("movement_queue_state", {axis = axis_index, size = axis_states[axis_index].queue_size})
end

local function flushAxesState(axis_index)
    axis_states[axis_index].break_request_event:set()
    axis_states[axis_index].ready_to_push_event:set()

    while axis_states[axis_index].running_coroutines_count > 0 do -- TODO replace with semaphore
        axis_states[axis_index].running_coroutines_count_changed_event:wait()
        axis_states[axis_index].running_coroutines_count_changed_event:clear()
    end
    axis_states[axis_index].break_request_event:clear()
    axis_states[axis_index].all_done_event:set()
    axis_states[axis_index].ready_to_push_event:set()
end

local uniqueMVId = 0
local function getNextMVID()
    uniqueMVId = uniqueMVId + 1
    return uniqueMVId
end

local handlers = {
    do_homing = function(args, sender)
        axis_states[args.axis].homing_lock:aquire()
        local defaultsSpeeds = utils.parseYAMLFile(path_lib.join(currentDir, "..","defaults","homing_speeds.yaml")) or {
            [1] = 0.02,
            [2] = 0.02,
            [3] = 0.02,
            [4] = 0.02,
            [5] = 0.02,
            [6] = 0.02,
            [7] = 0.02,
        }
        local speed = defaultsSpeeds[args.axis] or 6.28
        if type(args.speed) == "number" and  args.speed > 0 then
            speed = args.speed
        end
        actiongraph.SetParam(axis_graph_path(args.axis-1).."homingSpeed", speed)
        actiongraph.SendEvent(axis_graph_path(args.axis-1).."homingEventWaiter.event")
        local r = actiongraph.WaitEvent(axis_graph_path(args.axis-1).."homingDoneReporter.event", 20000)
        if r ~= nil then
            sender("homing_done", {axis = args.axis})
        else
            sender("homing_error", {axis = args.axis, error = "controller answer timeout"})
        end
        axis_states[args.axis].homing_lock:release()
        sender("command_status", {command="do_homing", ok=true})
    end,

    connection_status_request = function(args, sender)
        sender("connection_status", {is_online = actiongraph.IsRobotReady()})
        sender("command_status", {command="connection_status", ok=true})
    end,
    configure_pos_feedback = function(args, sender)
        actiongraph.SendEvent(axis_graph_path(args.axis-1).."positionReporter.stopper.event")
        if args.frequency > 0 then
            actiongraph.SetParam(axis_graph_path(args.axis-1).."positionReporter.frequency", args.frequency)
            actiongraph.SendEvent(axis_graph_path(args.axis-1).."positionReporter.starter.event")
        end
        sender("command_status", {command="configure_pos_feedback", ok=true})
    end,
    enqueue_movements = function(args, sender, session_id)
        local defaults = utils.parseYAMLFile(path_lib.join(currentDir, "..","..", "defaults","movements.yaml")) or {
            max_jerk = 100,
            max_acceleration = 20,
            max_speed = 10
        }

        local prepared_movements = {}
        for _, mv in ipairs(args.movements) do
            if prepared_movements[mv.axis] == nil then
                prepared_movements[mv.axis] = {}
            end
            local prepared_mv = {
                px = mv.position,
                vx = mv.velocity or 0,
                jerk_limit = mv.max_jerk or defaults.max_jerk,
                accel_limit = mv.max_acceleration or defaults.max_acceleration,
                speed_limit = mv.max_speed or defaults.max_speed,
                T = mv.T or 0,
                uniqueID = getNextMVID(),
                label = mv.label
            }
            table.insert(prepared_movements[mv.axis], prepared_mv)
        end

        for axis_id, mv_list in pairs(prepared_movements) do
            axis_states[axis_id].queue_size = axis_states[axis_id].queue_size + #mv_list
            sendMvQueueState(axis_id, sender)
        end
        -- local sequence_id = args.sequence_id or ""
        -- if movement_batch_locks[sequence_id] == nil then
        --     movement_batch_locks[sequence_id] = scheduler.NewLock()
        -- end
        -- movement_batch_locks[sequence_id]:aquire()


        local coroStates = {}

        local mv_results = {}

        for axis_index, movements in pairs(prepared_movements) do
           
            coroStates[axis_index] = scheduler.NewEvent()
            local movementEndsTaskFinishedEvent = scheduler.NewEvent()
            local movementEndsTask = scheduler.addTask(function()
                for _, mv in ipairs(movements) do
                    local r
                    local ts = millis()
                    while true do
                        local mv_args = actiongraph.WaitEvent(axis_graph_path(axis_index-1).."currentFinishedReporter.crtSender.event", axis_states[axis_index].break_request_event)
                        if axis_states[axis_index].break_request_event:is_set() then
                            -- sender("command_status", {command="enqueue_movements", ok=false, error="Movement batch was interrupted"})
                            movementEndsTaskFinishedEvent:set()
                            mv_results[axis_index] = "Movement is cancelled"
                            return
                        end
                        if mv_args and mv_args.param1 == mv.uniqueID then
                            r = mv_args
                            break
                        end
                        if millis() - ts > 60000 then
                            -- sender("command_status", {command="enqueue_movements", ok=false, error="Movement doesn't finish for too long", mv = mv})
                            movementEndsTaskFinishedEvent:set()
                            
                            mv_results[axis_index] = "Movement is not finished for too long"
                            return
                        end
                    end

                    if r ~= nil then
                        sender("movement_finished", {axis = axis_index, pos = r.param2, ts = r.ts/1e6, label = mv.label})
                    end
                end
                -- sender("command_status", {command="enqueue_movements", ok=true})
                mv_results[axis_index] = true
                movementEndsTaskFinishedEvent:set()
            end, string.format("movementEndsTask_%s_%s", axis_index, session_id))
            scheduler.addTask(function()

                axis_states[axis_index].running_coroutines_count = axis_states[axis_index].running_coroutines_count + 1
                axis_states[axis_index].running_coroutines_count_changed_event:set()

                axis_states[axis_index].lock:aquire()

                local qsize_expected = axis_states[axis_index].queue_size - #movements

                for _, mv in ipairs(movements) do
                    
                    if axis_states[axis_index].break_request_event:is_set() then
                        break
                    end
                    axis_states[axis_index].ready_to_push_event:wait()
                    axis_states[axis_index].ready_to_push_event:clear()

                    actiongraph.SetParam(axis_graph_path(axis_index-1).."px", mv.px)
                    actiongraph.SetParam(axis_graph_path(axis_index-1).."vx", mv.vx)
                    actiongraph.SetParam(axis_graph_path(axis_index-1).."jerk_limit", mv.jerk_limit)
                    actiongraph.SetParam(axis_graph_path(axis_index-1).."accel_limit", mv.accel_limit)
                    actiongraph.SetParam(axis_graph_path(axis_index-1).."speed_limit", mv.speed_limit)
                    actiongraph.SetParam(axis_graph_path(axis_index-1).."T", mv.T)
                    actiongraph.SetParam(axis_graph_path(axis_index-1).."uniqueMovementId", mv.uniqueID)
                
                    if axis_states[axis_index].break_request_event:is_set() then
                        break
                    end

                    actiongraph.SendEvent(axis_graph_path(axis_index-1).."startEventWaiter.event")

                    axis_states[axis_index].all_done_event:clear()

                    axis_states[axis_index].queue_size = axis_states[axis_index].queue_size - 1
                    sendMvQueueState(axis_index, sender)
                end
                if not axis_states[axis_index].break_request_event:is_set() then
                    axis_states[axis_index].ready_to_push_event:wait()
                end
                if axis_states[axis_index].break_request_event:is_set() then
                    axis_states[axis_index].queue_size = qsize_expected
                    sendMvQueueState(axis_index, sender)
                end

                
                axis_states[axis_index].lock:release()
                movementEndsTaskFinishedEvent:wait()
              
                coroStates[axis_index]:set()
                axis_states[axis_index].running_coroutines_count = axis_states[axis_index].running_coroutines_count - 1
                axis_states[axis_index].running_coroutines_count_changed_event:set()

            end, string.format("queueTask_%s_%s", axis_index, session_id))
        end
        for _, v in pairs(coroStates) do
            v:wait()
        end
      
        local finalOK = true
        local finalErr
        for axes, res in pairs(mv_results) do
            if res ~= true then
                finalOK = false
                if finalErr == nil then
                    finalErr = string.format("%s: %s", axes, res)
                else
                    finalErr = finalErr..string.format("\n%s: %s", axes, res)
                end
            else
                if finalErr == nil then
                    finalErr = string.format("%s: ok", axes)
                else
                    finalErr = finalErr..string.format("\n%s: ok", axes)
                end
            end
        end
        sender("command_status", {command="enqueue_movements", ok=finalOK, error=finalErr})
        -- movement_batch_locks[sequence_id]:release()

    end,
    stop = function(args, sender)
        actiongraph.SendEvent(axis_graph_path(args.axis-1).."breakEventWaiter.event")
        flushAxesState(args.axis)
        
        sender("command_status", {command="stop", ok=true})
    end
}


local sessionTable = {}

local json = require'json'
actiongraph.RegisterHostRPCCallback(function(msg)
    if msg.command ~= "user_custom_rpc" then
        return
    end
    local ok, err = schema_validator(msg)
    if ok == false then
        sendRPC("request_error", {what = err, request = msg})
        return
    end
    if sessionTable[msg.session_id] ~= nil then
        sendRPC("request_error", {what = "Duplicate session_id", request = msg})
        return
    end
    local session_id = msg.session_id
    if handlers[msg.type] == nil then
        sendRPC("request_error", {what = "Handler not found", request = msg}, session_id)
    end

    sessionTable[session_id] = true

    scheduler.addTask(function()
        local sender = function(ret_kind, ret_args, execerr)
            if execerr == nil then
                if ret_kind ~= nil then
                    sendRPC(ret_kind, ret_args or {}, session_id)
                end
            else
                sendRPC("request_error", {what = execerr, request = msg}, session_id)
            end
        end
        (handlers[msg.type])(msg.args, sender, session_id)
        sessionTable[session_id] = nil
    end)
end)

for axis_index = 0,motor_count-1 do

    local eventReadyToPush = scheduler.NewEvent()
    eventReadyToPush:set()

    local all_done_event = scheduler.NewEvent()
    all_done_event:set()


    table.insert(axis_states, {
        homing_lock = scheduler.NewLock(),
        queue_size  = 0,
        break_request_event = scheduler.NewEvent(),
        
        ready_to_push_event = eventReadyToPush,
        all_done_event = all_done_event,
        lock = scheduler.NewLock(),
        running_coroutines_count = 0,
        running_coroutines_count_changed_event = scheduler.NewEvent()
    })

    local axis_graph_path = graphPath..".".."a"..tostring(math.floor(axis_index)).."."
    actiongraph.EventHandler(axis_graph_path.."semifinishedReporter.event", function(args)
        -- utils.print(axis_index + 1, "DEBUG: current movement semifinished", args.ts/1e6, args.param1, args.param2)
        axis_states[axis_index + 1].ready_to_push_event:set()
    end)

    actiongraph.EventHandler(axis_graph_path.."allFinishedReporter.event", function(args)
        axis_states[axis_index + 1].all_done_event:set()
        -- utils.print(axis_index + 1, "all done")
    end)
    
    actiongraph.EventHandler(axis_graph_path.."currentFinishedReporter.crtSender.event", function(args)
        -- utils.print(axis_index + 1, "DEBUG: current movement finished", args.ts/1e6, args.param1, args.param2)
        sendRPC("pos_feedback", {axis = axis_index + 1, pos = args.param2, ts = args.ts/1e6})
    end)

    actiongraph.EventHandler(axis_graph_path.."mvErrorReporter.event", function(args)
        utils.print("Error on axis ", axis_index + 1)
        scheduler.addTask(function()
            for ai = 0,motor_count-1 do
                actiongraph.SendEvent(graphPath..".".."a"..tostring(ai)..".breakEventWaiter.event")
                flushAxesState(ai + 1)
                utils.print("Axis", ai + 1, "is stopped automatically")
            end
            sendRPC("movement_error", {axis = axis_index + 1})
        end)
    end)
  

    actiongraph.EventHandler(axis_graph_path.."positionReporter.reporter.event", function(args)
        sendRPC("pos_feedback", {axis = axis_index + 1, pos = args.x, ts = args.ts/1e6})
    end)
end

actiongraph.NamedEventHandler("EMERGENCY_BREAK_TRIGGERED", function(args)
    scheduler.addTask(function()
        -- scheduler.sleep(0.2)
        for ai = 0,motor_count-1 do
            flushAxesState(ai + 1)
        end
        sendRPC("emergency_stop_feedback", {ts = args.ts/1e6})
    end)
end)

actiongraph.DisconnectHandler(function()
    scheduler.addTask(function()
        for axis_index = 1,motor_count do
            flushAxesState(axis_index)
        end
        sendRPC("connection_status", {is_online = actiongraph.IsRobotReady()})
    end)
end)

actiongraph.ReadyHandler(function()
    scheduler.addTask(function()
        for axis_index = 0,motor_count-1 do
            actiongraph.SendEvent(axis_graph_path(axis_index).."breakEventWaiter.event")
            flushAxesState(axis_index + 1)
        end
        sendRPC("connection_status", {is_online = actiongraph.IsRobotReady()})
    end)
end)

if false then
    local UI = UI or {}
    UI.ButtonUserActions("Bad request", "", {
        UI.ActionCustomRPC({session_id = "1", type = "fuuuuu"})
    })
    UI.ButtonUserActions("Status", "", {
        UI.ActionCustomRPC({session_id = "2", type = "connection_status_request"})
    })

    UI.ButtonUserActions("Home 1", "", {
        UI.ActionCustomRPC({session_id = "3", type = "do_homing", args = {axis = 1}})
    })
    UI.ButtonUserActions("Home 1 fast", "", {
        UI.ActionCustomRPC({session_id = "3", type = "do_homing", args = {axis = 1, speed = 20}})
    })

    UI.ButtonUserActions("Home 3", "", {
        UI.ActionCustomRPC({session_id = "4", type = "do_homing", args = {axis = 3}})
    })

    UI.ButtonUserActions("POS FDBCK 1, 1HZ", "", {
        UI.ActionCustomRPC({session_id = "6", type = "configure_pos_feedback", args = {axis = 1, frequency = 1}})
    })
    UI.ButtonUserActions("POS FDBCK 1, 5HZ", "", {
        UI.ActionCustomRPC({session_id = "7", type = "configure_pos_feedback", args = {axis = 1, frequency = 5}})
    })
    UI.ButtonUserActions("POS FDBCK 1, OFF", "", {
        UI.ActionCustomRPC({session_id = "8", type = "configure_pos_feedback", args = {axis = 1, frequency = 0}})
    })

    UI.ButtonUserActions("MV1,2 10->20", "", {
        UI.ActionCustomRPC({session_id = "9", type = "enqueue_movements", args = {
            movements = {
                {axis = 1, position = 10},
                {axis = 1, position = 20},
                {axis = 1, position = 10},
                {axis = 1, position = 20},
                {axis = 2, position = 10},
                {axis = 2, position = 20}
            },
            sequence_id = "another_sequence"
        }})
    })

    UI.ButtonUserActions("MV(err)", "", {
        UI.ActionCustomRPC({session_id = "92", type = "enqueue_movements", args = {
            movements = {
                -- {axis = 1, position = 10},
                -- {axis = 1, position = 20},
                -- {axis = 1, position = 10},
                -- {axis = 1, position = 20},
                -- {axis = 2, position = 10},
                -- {axis = 2, position = 20},
                -- {axis = 3, position = 5},
                -- {axis = 3, position = 10},
                {axis = 3, position = 5, T = 0.0001},
                {axis = 2, position = 5, T = 0.0001},
                {axis = 1, position = 5, T = 0.0001}
            },
            sequence_id = "another_sequence"
        }})
    })

    UI.ButtonUserActions("MV1 10->20 (s90)", "", {
        UI.ActionCustomRPC({session_id = "90", type = "enqueue_movements", args = {movements = {
            {axis = 1, position = 10, T=0, label = "mv 1"},
            {axis = 1, position = 20, T=0, label = "mv 2"}
        }}})
    })
    UI.ButtonUserActions("MV2 10->20 (s91)", "", {
        UI.ActionCustomRPC({session_id = "91", type = "enqueue_movements", args = {movements = {
            {axis = 2, position = 10, T=0, label = "mv 3"},
            {axis = 2, position = 20, T=0, label = "mv 4"},
        }}})
    })

    UI.ButtonUserActions("MV2 -> 0 (s95)", "", {
        UI.ActionCustomRPC({session_id = "95", type = "enqueue_movements", args = {movements = {
            {axis = 2, position = 0, T=0, label = "mv 3"},
        }}})
    })


    UI.ButtonUserActions("MV ALL", "", {
        UI.ActionCustomRPC({session_id = "10", type = "enqueue_movements", args = {movements = {
            {axis = 1, position = 25, T=10},
            {axis = 1, position = 20, T=10},
            {axis = 2, position = 27, T=10},
            {axis = 2, position = 22, T=10},
            {axis = 3, position = 24, T=10},
            {axis = 3, position = 22, T=10},
            {axis = 4, position = 26, T=10},
            {axis = 4, position = 19, T=10},
            {axis = 5, position = 22, T=10},
            {axis = 5, position = 21, T=10},
            {axis = 6, position = 26, T=10},
            {axis = 6, position = 24, T=10},
            {axis = 7, position = 30, T=10},
            {axis = 7, position = 27, T=10},
        }}})
    })

    UI.ButtonUserActions("STOP1", "", {
        UI.ActionCustomRPC({session_id = "11", type = "stop", args = {axis = 1}})
    })
    UI.ButtonUserActions("STOP2", "", {
        UI.ActionCustomRPC({session_id = "12", type = "stop", args = {axis = 2}})
    })

    for id = 1,5 do 
        UI.ButtonActions(string.format("0->GPIO#%s", id+20), "", {
            UI.ActionSetParam("Hardware.GPIOControlModule.hal_id", 20+id),
            UI.ActionSetParam("Graph.gpioControl.gpioValueToWrite", 0),
            UI.ActionSendNamedEvent("WRITE_GPIO")
        })

    end
    for id = 1,5 do 
        UI.ButtonActions(string.format("1->GPIO#%s", id+20), "", {
            UI.ActionSetParam("Hardware.GPIOControlModule.hal_id", 20+id),
            UI.ActionSetParam("Graph.gpioControl.gpioValueToWrite", 1),
            UI.ActionSendNamedEvent("WRITE_GPIO")
        })

    end
    for id = 1,5 do 
        UI.ButtonActions(string.format("GPIO#%s->", id+30), "", {
            UI.ActionSetParam("Hardware.GPIOControlModule.hal_id", 30+id),
            UI.ActionSendNamedEvent("READ_GPIO")
        })
    end
    UI.SetRPCLogsVisible(true)

end
