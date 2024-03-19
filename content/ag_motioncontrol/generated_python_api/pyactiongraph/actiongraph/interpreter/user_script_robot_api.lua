return function (robot, lowlevelAGAPI)
    return {
        RobotID = function()
            return robot.ID
        end,
        RobotSerial = function()
            return robot.Serial
        end,
        IsRobotReady = function()
            return lowlevelAGAPI:IsRobotReady()
        end,
      
        SendMessageToHal = function(...)
            lowlevelAGAPI:SendMessageToHal(...)
        end,
        HALRequest = function(...)
            return lowlevelAGAPI:HALRequest(...)
        end,
        HALMessageHandler = function(id, h)
            lowlevelAGAPI:HALMessageListener(id, h)
        end,
        SendNamedEvent = function(id)
            robot:SendNamedEvent(id)
        end,
    
        SendEvent = function(eventParamPath)
            robot:SendEvent(eventParamPath)
        end,
    
        NamedEventHandler = function(id, f)
            robot:SetNamedEventHandler(id, f)
        end,
    
        EventHandler = function(eventParamPath, f)
            robot:SetEventHandler(eventParamPath, f)
        end,

        WaitNamedEvent = function(id, timout)
            return robot:WaitNamedEvent(id, timout)
        end,
    
        WaitEvent = function(eventParamPath, timout)
            return robot:WaitEvent(eventParamPath, timout)
        end,
        
        SetParam = function(path, value)
            return robot:SetParam(path, value)
        end,

        GetParam = function(path)
            return robot:GetParam(path)
        end,

        ReadyHandler = function(f)
            lowlevelAGAPI:SetReadyCallback(f)
        end,
        DisconnectHandler = function(f)
            lowlevelAGAPI:SetDisconnectCallback(f)
        end,
    }
end