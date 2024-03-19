local P = {}   -- package

local ag_utils = require'interpreter.helpers'
local utils = require'utils'
local log = ag_utils.log
log = function(...)end

local ipairs = ipairs
local pairs = pairs
local error = error
local table = table
local tostring = tostring
local globalEnv = _ENV
local _ENV = P


local HWNamesMapping = {
    ANALOG_OUTPUT_SIGNAL = "ANALOG_OUTPUT_SIGNAL_HW_MODULE",
    ANALOG_INPUT_SIGNAL = "ANALOG_INPUT_SIGNAL_HW_MODULE",
    BASIC_PID_CONTROLLER = "BASIC_PID_MOTOR_MOVABLE_HW_MODULE",
    LINEAR_DELTA_ROBOT = "LINEAR_ACTUATORS_DELTA_ROBOT_MOVABLE_HW_MODULE",
    ROTATING_DELTA_ROBOT = "DELTA_ROBOT_MOVABLE_HW_MODULE",
    DIGITAL_INPUT_SIGNAL = "DIGITAL_INPUT_SIGNAL_HW_MODULE",
    DIGITAL_OUTPUT_SIGNAL = "DIGITAL_OUTPUT_SIGNAL_HW_MODULE",
    MOVABLE_COORD_SYSTEM_TRANSFORM = "MOVABLE_COORD_SYSTEM_TRANSFORM_MOVABLE_HW_MODULE"
}

local NodeNamesMapping = {
    MOVEMENT = "MOVEMENT2"
}

local ParamsNamesMapping = {
    BASIC_PID_CONTROLLER = {feedback_signal="encoder_signal"},
    LINEAR_DELTA_ROBOT = {
        actuator0="actuator0_id",
        actuator1="actuator1_id",
        actuator2="actuator2_id"
    },
    ROTATING_DELTA_ROBOT = {
        actuator0="actuator0_id",
        actuator1="actuator1_id",
        actuator2="actuator2_id"
    },
    MOVABLE_COORD_SYSTEM_TRANSFORM = {
        scale="scale_x",
        rot_axis="rot_axis_x",
        translation="translation_x"
    }
}

local NodeParamsNamesMapping = {
    MOVEMENT2 = {
        px="x",
        py="y",
        pz="z",
        p="x",
        v="vx",
        a="ax"
    },
    MOVABLE_STATUS_SAVER = {
        px="x",
        py="y",
        pz="z",
        p="x",
        v="vx"
    },
    MOVEMENT = {
        px="x",
        py="y",
        pz="z",
        p="x",
        v="vx"
    },
    CONST_SPEED_MOVEMENT = {
        p="px",
    },
    CALIBRATER = {
        px="x",
        py="y",
        pz="z",
        p="x"
    },
    POSITION_DETECTOR = {
        px="x",
        py="y",
        pz="z",
        p="x"
    }
}

function NewLegacyTranslator(mainModule, api)

    local R = {
        mainContext = mainModule,
        emitters = {},
        createdNodes = {},
        createdParams = {},
        createdHWModules = {},
        autoIDMap = {},
        api = api
    }

    function R:emitParam(entity, sourceType, dontCheckSrcType)
        log("Creating param", entity or "nil", sourceType or "nil", entity:Parent() or "nil")

        -- if entity:Parent().OptionalParams[v]
        local assignedType, assignedValue
        local prm
        if entity.AssignedParam then
            assignedType = entity.AssignedParam.Type
            assignedValue = entity.AssignedParam.Value
        else
            assignedType = entity.Type
            assignedValue = entity.Value
        end
        -- if requiredParam.Type ~= assignedType then
        --     error("bad state")
        -- end

        if (sourceType == "Float" and (assignedType == "Integer" or assignedType == "Float")) or
                (sourceType == "Alias" and assignedType == "Float") or
                (dontCheckSrcType and assignedType == "Float") or
                (sourceType == "ANY_LOWLEVEL" and assignedType == "Float") then
            if assignedValue == nil and entity.Mutable == true then
                assignedValue = 0
            end
            if assignedValue ~= nil then --TODO
                prm = self.api:ParamFloat(assignedValue)
            end
            log("ParamFloat")
        elseif (sourceType == "Integer" and (assignedType == "Integer" or assignedType == "Float"))
                or(sourceType == "Alias" and assignedType == "Integer")or
                (dontCheckSrcType and assignedType == "Integer") or
                (sourceType == "ANY_LOWLEVEL" and assignedType == "Integer")
                then
            -- log(assignedValue)
            if assignedValue == nil and entity.Mutable == true then
                assignedValue = 0
            end
            if assignedValue ~= nil then --TODO
                prm = self.api:ParamInt(assignedValue)
            end
            log("ParamInt")
        elseif ((sourceType == "Integer" or sourceType == "Float" or sourceType == "Vector" or sourceType == "ByteString") and assignedType == "Expression") or
                (sourceType == "Alias" and assignedType == "Expression") or
                (sourceType == "ANY_LOWLEVEL" and assignedType == "Expression") or
                (dontCheckSrcType and assignedType == "Expression") 
                then
            local tokenList = {}
            for _, token in ipairs(assignedValue) do
                if token.actiongraphParam ~= nil then
                    if R.createdParams[token.actiongraphParam] == nil then
                        log("Param not created ", token.actiongraphParam)
                        error("Param not created ")
                    end
                    table.insert( tokenList, R.createdParams[token.actiongraphParam] )
                else
                    local toTest = token.op or token.f0 or token.f1 or token.f2 or token.f3 or token.f4 or token.f5
                    if toTest ~= nil then
                        if self.api.EXPR[toTest.ID] == nil then
                            error("Unknown expr op")
                        end
                        table.insert( tokenList, self.api.EXPR[toTest.ID] )
                    else
                        error("unkown expression token type ".. token)
                    end
                end
            end
            prm = self.api:ParamExpression(tokenList)
        elseif sourceType == "PC_EVENT_ID" or
            (dontCheckSrcType and assignedType == "PC_EVENT_ID")  then
            log("ParamInt")
            local eventIdMapKey = entity.AssignedParam or entity
            if self.autoIDMap[eventIdMapKey] == nil then
                self.autoIDMap[eventIdMapKey] = self.autoIDCOunter
                self.autoIDCOunter = self.autoIDCOunter + 1
            end
            prm = self.api:ParamInt(self.autoIDMap[eventIdMapKey])
        elseif sourceType == "Vector" and assignedType == "Vector" or
            (sourceType == "ANY_LOWLEVEL" and assignedType == "Vector")
            then
            -- utils.errorExt("Unimplemented")
            if assignedValue == nil and entity.Mutable == true then
                assignedValue = {0, 0, 0}
            end
            prm = self.api:ParamVector(assignedValue[1], assignedValue[2], assignedValue[3])
        elseif sourceType == "ByteString" and assignedType == "ByteString" or
            (sourceType == "ANY_LOWLEVEL" and assignedType == "ByteString")
            then
            -- utils.errorExt("Unimplemented")
            if assignedValue == nil and entity.Mutable == true then
                assignedValue = ""
            end
            prm = self.api:ParamString(assignedValue)
        else 
            log(sourceType, assignedType, entity)
            utils.errorExt(sourceType, assignedType, assignedValue)
            error("bad param type")
        end

        if entity.Mutable == true then
            entity.SetValue = function(slf, val)
                return prm.Set(val)
            end
            entity.GetValue = function(slf)
                return prm.Get()
            end
        end

        if entity.Type == "Expression" then
            entity.GetValue = function(slf)
                return prm.Get()
            end
        end

        self.createdParams[entity] = prm
    end

    function R:emitHW(entity, paramMap)

        log("HW MODULE", entity.Type)

        local idVal = self.hwIDCounter
        self.hwIDCounter = self.hwIDCounter + 1

        self.createdParams[entity] = self.api:ParamInt(idVal)
        log("HW ID PARAM", entity, self.createdParams[entity])
        local HWLegacyName = entity.Type
        if HWNamesMapping[HWLegacyName] then
            HWLegacyName = HWNamesMapping[HWLegacyName]
        end

        if self.api.hardwareClasses[HWLegacyName] == nil then
            error("Unknown module type: " .. HWLegacyName)
        end


        local preparedParams = {}
        for prmId, requiredParam in pairs(entity.Configuration.Parameters) do --looks like aliases are not handled correctly here
            local p = paramMap[requiredParam]
            log(prmId, p)
            if p == nil and entity.OptionalParams[prmId] == true then

            else
                local toSearch = p
                if p:EntityType() == "HWModule" then
                    toSearch = p:GetMainBasicModule()
                end

                if self.createdParams[toSearch] == nil and (entity.OptionalParams == nil or entity.OptionalParams[prmId] == nil) then
                    log("Param unavailable at this point: ", p)
                    error(".")
                end
                
                local mappedName = prmId
                if ParamsNamesMapping[entity.Type] and ParamsNamesMapping[entity.Type][mappedName] then
                    mappedName = ParamsNamesMapping[entity.Type][mappedName]
                end

                preparedParams[mappedName] = self.createdParams[toSearch]
            end
        end
        self.api:HardwareEntity(idVal, self.api.hardwareClasses[HWLegacyName], entity.Autostart, preparedParams).WithAlias(entity:AbsolutePath(), true)
    end

    function R:emitNode(entity, paramMap)
        log("NODE", entity)
    
        local NodeLegacyName = entity.Type
        if NodeNamesMapping[NodeLegacyName] then

            NodeLegacyName = NodeNamesMapping[NodeLegacyName]
        end

        if self.api.actionClasses[NodeLegacyName] == nil then
            error("Unknown node type: ", entity.Type)
        end
        local preparedParams = {}
        local eventHandler
        local paramToSetupEventWaiter
        for prmId, requiredParam in pairs(entity.Configuration.Parameters) do --looks like aliases are not handled correctly here
           
            local pp = paramMap[requiredParam]
            if pp == nil and entity.OptionalParams[prmId] == true then

            else

                local p = pp
                if pp:EntityType() == "HWModule" then
                    p = pp:GetMainBasicModule()
                end
                log(prmId, p)

                -- log(entity.OptionalParams)
                if self.createdParams[p] == nil and (entity.OptionalParams == nil or entity.OptionalParams[prmId] == nil) then
                    log("Param unavailable at this point: ", p, entity)
                    error(".")
                end
                if p.Type == "PC_EVENT_ID" and entity.IsPCEventEmitter == true then
                    -- log("HERE")

                    eventHandler = function(...) 
                        p.EventHandler(entity, ...)
                    end
                end

                if p.Type == "PC_EVENT_ID" and entity.IsPCEventWaiter == true then
                    -- log("HERE")
                    paramToSetupEventWaiter = p
                
                end

                local mappedName = prmId
                if NodeParamsNamesMapping[entity.Type] and NodeParamsNamesMapping[entity.Type][mappedName] then
                    mappedName = NodeParamsNamesMapping[entity.Type][mappedName]
                end

                preparedParams[mappedName] = self.createdParams[p]

            end
        end

       


        local newNode = self.api:Action(self.api.actionClasses[NodeLegacyName], preparedParams).WithAlias(entity:AbsolutePath(), true)
        if eventHandler ~= nil then
            -- log("#######")
            if entity.IsPCEventEmitter ~= true then 
                error("Cannot attach event handler to node that doesn't emit events")
            end
            newNode.WithEventCallback(eventHandler)
        end

        if paramToSetupEventWaiter ~= nil then
            paramToSetupEventWaiter.SendEvent = function()
                self.api:SendEvent(newNode)
            end
        end
        self.createdNodes[entity] = newNode
    end
    
    function R:emitConnections(entity)
        log("CONNECTION")
      
        local slotParsers = {
            start = function(n)
                -- log("Start", n.alias)
                return self.api:Start(n)
            end,
            stop = function(n) 
                -- log("Stop", n.alias)
                return self.api:Stop(n)
            end,
            cancel = function(n)
                -- log("Cancel", n.alias)
                return self.api:Cancel(n)
            end
        }

        local eventParsers = {
            started = function(n)  
                -- log("Started", n.alias)
                return self.api:Started(n)
            end,
            stopped = function(n)
                -- log("Stopped", n.alias)
                return self.api:Stopped(n)
            end,
            erred = function(n) 
                -- log("Erred", n.alias)
                return self.api:Erred(n) 
            end
        }

        local whatList = {}
        local whenList = {}
        -- log("WHEN")
        for _, event in ipairs(entity.When) do
            local node = self.createdNodes[event:Parent().SyncerNode or event:Parent()]
            if node == nil then
                error("Unknown node "..tostring(event:Parent()))
            end

            local h = eventParsers[event:ID()]
            if h == nil then
                error("Unknown event "..event:ID())
            end

            table.insert( whenList, h(node) )
        end
        -- log("DO")
        for _, action in ipairs(entity.What) do
            local node = self.createdNodes[action:Parent().SyncerNode or action:Parent()]
            if node == nil then
                error("Unknown node")
            end

            local h = slotParsers[action:ID()]
            if h == nil then
                error("Unknown action to do "..action:ID())
            end

            table.insert( whatList, h(node) )
        end
       


        self.api:When(table.unpack(whenList)).Do(table.unpack(whatList))
    end

    function R:emitEntryPoint(entity)
        local entry = R.createdNodes[entity.Node]
        log("Creating entry point", entry)
        self.api:SetGraphEntryNode(entry)
    end

    R.emitters.Parameter = R.emitParam
    R.emitters.HWModule = R.emitHW
    R.emitters.Graph = R.emitNode
    R.emitters.Connection = R.emitConnections
    R.emitters.EntryPoint = R.emitEntryPoint

    function R:run()
        self.createdNodes = {}
        self.createdParams = {}
        self.createdHWModules = {}
        self.autoIDMap = {}
        self.autoIDCOunter = 0
        self.hwIDCounter = 0
      
        self.mainContext:IterateAllEmbeddedEntitiesDependencyTreeBottomToTop(function(e, ...)
            if self.emitters[e:EntityType()] == nil then
                error("Unknown entity type")
            end
            self.emitters[e:EntityType()](self, e, ...)
           
        end)
       
       
    end
    return R
end


return P
