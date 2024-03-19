
local utils = require"utils"
local json = require"json"
return function (rpc)
    local genericCallbacks = {}
    local kbdCallbacks = {}
    local mouseCallbacks = {}
    return {
        api = function(robotID) return {
            RegisterHostRPCCallback = function(f)
                table.insert(genericCallbacks, f)
            end,
            SendHostRPC = function(obj) rpc:Send(obj) end,
            RegisterIDEKeyboardCallback = function(f, all)
                table.insert(kbdCallbacks, {f, all or robotID})
            end,
            RegisterIDEMouseCallback = function(f, all)
                table.insert(mouseCallbacks, {f, all or robotID})
            end
        } end,


        dispatcher = function(robots)
            return function(request)
                if request.command == "ide_user_event" then
                    if request['type'] == "mouse_click" then
                        for _, f_and_id in ipairs(mouseCallbacks) do
                            if f_and_id[2] == true or f_and_id[2] == request.robot_id then
                                f_and_id[1](request.params)
                            end
                        end
                        
                    elseif request['type'] == "keyboard_pressed" then
                        for _, f_and_id in ipairs(kbdCallbacks) do
                            if f_and_id[2] == true or f_and_id[2] == request.robot_id then
                                f_and_id[1](request.params)
                            end
                        end
                    else
                        utils.print("Unsupported IDE RPC command type")
                    end
                elseif request.command == "ide_actiongraph_control_request"  then
                    if request.robot_id ~= '*' then
                        if type(request.robot_id) == "string" then
                            request.robot_id = {request.robot_id};
                        end
                        if type(request.robot_id) ~= "table" then
                            utils.print("robot_id should be a list of robot IDs")
                            return
                        end
                        for _, id in ipairs(request.robot_id) do
                            if robots[id] == nil then
                                utils.print("Uknown target robot ID:", id)
                                return
                            end
                        end
                    end
                    local target_ids = request.robot_id
                    if target_ids == '*' then
                        target_ids = {}
                        for _, id in ipairs(request.robot_id) do
                            table.insert(target_ids, id)
                        end
                    end
                    if type(request.args) ~= "table" then 
                        utils.print("Invalid args type")
                        return
                    end
                    local action
                    if request.kind == "send_named_event" then
                        action = function(robot) robot:SendNamedEvent(request.args.event_name) end
                    elseif request.kind == "send_event" then
                        action = function(robot) robot:SendEvent(request.args.event_param_path) end
                    elseif request.kind == "set_param" then
                        action = function(robot) 
                            -- utils.print("Setting param ", request.args.param_path, " to ", json.stringify(request.args.param_value))
                            robot:SetParam(request.args.param_path, request.args.param_value) 
                        end
                    else
                        utils.print("Unsupported actiongraph RPC command kind")
                    end

                    for _, id in ipairs(target_ids) do
                        action(robots[id])
                    end
                else
                    for _, f in ipairs(genericCallbacks) do
                        f(request)
                    end
                end
            end
        end
    } 
end