local utils = require'utils'


return function (rpc)
    local ret= {
        controls = {},
        rpc_log_windows_visible = {}
    }

    function ret.GetAPI (robotActionGraphContext)
        if ret.controls[robotActionGraphContext.ID] == nil then
            ret.controls[robotActionGraphContext.ID] = {}
            ret.rpc_log_windows_visible[robotActionGraphContext.ID] = false
        end
        local function action(kind, args)
            local r = {
                command = "ide_actiongraph_control_request",
                robot_id = robotActionGraphContext.ID,
                kind = kind,
                args = args
            }
            return r
        end
        local function user_action(obj)
            obj.command = "user_custom_rpc"
            obj.robot_id = robotActionGraphContext.ID
            if type(obj.args) ~= "table" then
                obj.args = {}
            end
            return obj
        end
        local controlUniqueID = 0
        function UIUniqueID()
            controlUniqueID = controlUniqueID + 1
            return controlUniqueID
        end
        return {
            ActionSetParam = function(paramPath, value)
                return action("set_param", {param_path = paramPath, param_value = value})
            end,
            ActionSendEvent = function(eventParamPath)
                return action("send_event", {event_param_path = eventParamPath})
            end,
            ActionSendNamedEvent = function(eventName)
                return action("send_named_event", {event_name = eventName})
            end,
            ButtonActions = function(caption, description, actionList)
                if type(caption) ~= "string" or caption:len() == 0 then
                    utils.errorExt("caption should not be empty")
                end
                table.insert(ret.controls[robotActionGraphContext.ID], {
                    kind = 'Button', opts = { caption = caption, description = description},
                    action = actionList
                })
            end,
            ActionCustomRPC = function(obj)
                return user_action(obj)
            end,
            ButtonUserActions = function(caption, description, actionList)
                if type(caption) ~= "string" or caption:len() == 0 then
                    utils.errorExt("caption should not be empty")
                end
                table.insert(ret.controls[robotActionGraphContext.ID], {
                    kind = 'Button', opts = { caption = caption, description = description},
                    action = actionList
                })
            end,
            ButtonSetParam = function(paramPath, value, caption, description)
                if not description then
                    description = string.format("Set parameter '%s' to '%s'", paramPath, value)
                end
                if not caption then
                    caption = string.format("%s -> %s", value, paramPath)
                end
                table.insert(ret.controls[robotActionGraphContext.ID], {
                    kind = 'Button', opts = { caption = caption, description = description},
                    action = {action("set_param", {param_path = paramPath, param_value = value})}
                })
            end,
            InputSetParam = function(paramPath, caption, description)

                if not description then
                    description = string.format("Edit parameter '%s'", paramPath)
                end
                if not caption then
                    caption = string.format("Edit %s", paramPath)
                end
                local ptype, mutable = robotActionGraphContext:getParamType(paramPath)
                if mutable ~= true then
                    utils.errorExt("Cannot change non-mutable parameter")
                end
                table.insert(ret.controls[robotActionGraphContext.ID], {
                    kind = 'ParameterInput', opts = { caption = caption, description = description, 
                        target_arg_name = "param_value",
                        param_type = ptype
                    },
                    action = {action("set_param", {param_path = paramPath, param_value = nil})}
                })
            end,
            ButtonSendEvent = function(eventParamPath, caption, description)
                if not description then
                    description = string.format("Send event '%s'", eventParamPath)
                end
                if not caption then
                    caption = string.format("Send %s", eventParamPath)
                end
                table.insert(ret.controls[robotActionGraphContext.ID], {
                    kind = 'Button', opts = { caption = caption, description = description},
                    action = {action("send_event", {event_param_path = eventParamPath})}
                })
            end,
            ButtonSendNamedEvent = function(eventName, caption, description)
                if not description then
                    description = string.format("Send event '%s'", eventName)
                end
                if not caption then
                    caption = string.format("Send <%s>", eventName)
                end
                table.insert(ret.controls[robotActionGraphContext.ID], {
                    kind = 'Button', opts = { caption = caption, description = description},
                    action = {action("send_named_event", {event_name = eventName})}
                })
            end,
            LinearAxisVisualiser = function(graphPathToMovable, min, max, coord_component, caption, description)
                if not coord_component or ({x=true, y=true, z=true})[coord_component] ~= true then
                    utils.print("Coordinate component not set for AxisPositionVisualiser, using 'x'")
                    coord_component = 'x'
                end
                if not description then
                    description = string.format("Movable '%s' position, coordinate '%s'", graphPathToMovable, coord_component)
                end
                if not caption then
                    caption = string.format("'%s': %s", graphPathToMovable, coord_component)
                end

                local ID = UIUniqueID()
                table.insert(ret.controls[robotActionGraphContext.ID], {
                    ID = ID,
                    kind = 'LinearAxisVisualiser', opts = {
                        caption = caption,
                        description = description,
                        min=min,
                        max=max
                    },
                    action = {}
                })
                
                robotActionGraphContext:SetEventHandler(graphPathToMovable..".event", function(args)
                    rpc:Send({command="actiongraph_ui_feedback", control_id = ID, args={ts = args.ts, value=args[coord_component]}})
                end)
            end,
            RotaryAxisVisualiser = function(graphPathToMovable, coord_component, caption, description)
                if not coord_component or ({x=true, y=true, z=true})[coord_component] ~= true then
                    utils.print("Coordinate component not set for AxisPositionVisualiser, using 'x'")
                    coord_component = 'x'
                end
                if not description then
                    description = string.format("Movable '%s' position, coordinate '%s'", graphPathToMovable, coord_component)
                end
                if not caption then
                    caption = string.format("'%s': %s", graphPathToMovable, coord_component)
                end

                local ID = UIUniqueID()
                table.insert(ret.controls[robotActionGraphContext.ID], {
                    ID = ID,
                    kind = 'RotaryAxisVisualiser', opts = {
                        caption = caption,
                        description = description
                    },
                    action = {}
                })
                
                robotActionGraphContext:SetEventHandler(graphPathToMovable..".event", function(args)
                    rpc:Send({command="actiongraph_ui_feedback", control_id = ID, args={ts = args.ts, value=args[coord_component]}})
                end)
            end,
            SetRPCLogsVisible = function(val)
                ret.rpc_log_windows_visible[robotActionGraphContext.ID] = val == true
            end
        }
    end

    function ret.SendUIConfig ()
        for id, ui_controls in pairs(ret.controls) do
            rpc:Send({command="actiongraph_ui_config", robot_id = id, controls=ui_controls, rpc_log_windows_visible=ret.rpc_log_windows_visible[id]})
        end
    end

    return ret
end