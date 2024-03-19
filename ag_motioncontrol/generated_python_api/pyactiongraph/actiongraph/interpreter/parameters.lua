local ag_utils = require'interpreter.helpers'
local utils = require'utils'
local OrderedTable = require"orderedtable"
local Vector = require'vector'
local rpn = require'interpreter.rpn'
function CreateParam(src, parentEntity, name, moduleContext, robotContext)
   
    local param = {}
    param.Mutable = false
    param.dependencyList = {}

    if src == ag_utils.SRC_NULL then
        param.Type = "Alias"
    elseif type(src) == "number" then
        param.Type = "Float"
        param.Value = src
        -- log("HERE", param.Value)
    elseif type(src) == "boolean" then
        param.Type = "Integer"
        if src == true then 
            param.Value = 1
        else
            param.Value = 0
        end
    elseif type(src) == "string" then
        src = ag_utils.trimString(src)
        if src:sub(1, 1) == "=" then
            -- error("Expression param not implemented")
            local parsedExpr = rpn.calcPostfixForm(src:sub(2))
            param.Type = "Expression"
            param.Value = parsedExpr
        elseif src:sub(1, 1) == "<" and src:sub(#src, #src) == ">" then
            param.Type = "PC_EVENT_ID"
            param.Value = ag_utils.trimString(src:sub(2, #src-1))
        elseif src:sub(1, 1) == "/" and src:sub(#src, #src) == "/" then
            param.Type = "ByteString"
            param.Value = src:sub(2, #src-1)
        else
            param.Type = "Alias"
            param.Value = src
        end
      
    elseif type(src) == "table" then
        if type(src[1]) == "number" and type(src[2]) == "number" and type(src[3]) == "number" and #src == 3 then
            param.Type = "Vector"
            param.Value = Vector(src[1], src[2], src[3])
        else
            param.Type = src.Type
            param.Value = src.Value

            param.Mutable = src.Mutable == true

            if param.Type == "Expression" then
                if type(param.Value) == "string" and param.Value:sub(1, 1) == "=" then
                    -- error("Expression param not implemented")
                    local parsedExpr = rpn.calcPostfixForm(param.Value:sub(2))
                    param.Value = parsedExpr
                else
                    utils.errorExt("Unsupported param value in param definition")
                end
            elseif param.Type == "Vector" then
                if src.Value ~= nil then
                    if type(src.Value[1]) == "number" and type(src.Value[2]) == "number" and type(src.Value[3]) == "number" and #src.Value == 3 then
                        param.Value = Vector(src.Value[1], src.Value[2], src.Value[3])
                    else
                        utils.errorExt("Bad vector value")
                    end
                end
            elseif param.Type == "Integer" or param.Type == "Float" then
                if src.Value ~= nil then
                else
                    -- param.Value = 0
                end
            elseif param.Type == "ByteString" then
                src.Value = tostring(src.Value)
            elseif param.Type == "PC_EVENT_ID" then
                if src.Value ~= nil then
                    utils.errorExt("unexpected", param.Type)
                end
            elseif param.Type == "ANY_LOWLEVEL" then
                
            else
                utils.errorExt("Unsupported param type in param definition: ", param.Type)
            end
        end
        
        -- if src.GetValueMeta == nil then 
        --     utils.error("Bad src data: ")
        -- end
    else
        error("Unsupported param type in param definition")
    end

    if param.Type == nil then
        utils.errorExt("Unknown parameter type")
    end
    
    param.id = name
    param.ownerEntity = parentEntity
    param.ModuleContext = moduleContext
    param.RobotContext = robotContext

    if param.Mutable == true then
        -- ag_utils.log("Mutable param:", self)
    end
    function param:Assign(param)
        -- log("Assigning param ", param.Name, ":", param.Type, "to param", self.Name, ":", self.Type)
        self.AssignedParam  = param
    end

    function param:ToString()
        local ass = self.AssignedParam or {}
        return string.format( "Type:%s Value:%s AssignedType:%s AssignedValue:%s Mutable:%s" , self.Type, self.Value, ass.Type, ass.Value, self.Mutable)
    end
    function param:ID()
        return self.id
    end

    function param:Parent()
        if self.ownerEntity and self.ownerEntity:EntityType() == "Configuration" and self.ownerEntity:Parent() ~= nil then
            -- log("here")
            return self.ownerEntity:Parent()
        end
        return self.ownerEntity
    end

    function param:Children()
        return OrderedTable()
    end

    function param:AliasTarget()
        if self.AssignedParam and self.AssignedParam.Type == "Alias" then
            return self.AssignedParam.Value
        end
        if self.Type == "Alias" then
            return self.Value
        end
    end

    function param:GetFinalAssignedEntity()
        local toHandle = self.AssignedParam or self
        if toHandle.Type == "Alias" then
            toHandle = toHandle:ResolvePath(".")
        end
        if toHandle == nil then 
            return nil
        end
        if toHandle:EntityType() == "Parameter" and toHandle.AssignedParam then
            return toHandle.AssignedParam
        end
        return toHandle
    end
    function param:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
        -- ag_utils.log(self)
        local alreadyVisited = alreadyVisited or {}

        local toHandle = self:GetFinalAssignedEntity()
        if toHandle == nil then 
            ag_utils.log("Unresolved: ", self, self:Parent()) 
            error(".")
        end
        local typeCheckOk = true
        if self.Type == "Float" or self.Type == "Vector" or self.Type == "Vector" then
            if toHandle.Type ~= "Float" and toHandle.Type ~= "Vector" and toHandle.Type ~= "Expression" then
                typeCheckOk = false
            end
        end

        if self.Type == "Integer" then
            if toHandle.Type ~= "Float" and toHandle.Type ~= "Integer" and toHandle.Type ~= "Expression"and toHandle:EntityType() ~= "HWModule" then
                typeCheckOk = false
            end
        end

        -- TODO ????
        --[[
        if self.Type == "PC_EVENT_ID" and toHandle.Type ~= "PC_EVENT_ID" then
            ag_utils.log("HERE")
            if toHandle.Type == "Alias" then 
                ag_utils.log("HERE")
                toHandle = CreateParam("<"..self:AbsolutePath()..">", self:Parent(), "auto_PC_EVENT_ID", self.ModuleContext, self.RobotContext)
                self.AssignedParam = toHandle
            else
                typeCheckOk = false
            end
            
        end
        --]]

        -- TODO this should be refactored, because it mutates state
        if self.Type == "PC_EVENT_ID" and self == toHandle and self.Value == nil then 
            -- ag_utils.log("HERE")
            toHandle = CreateParam("<"..self:AbsolutePath()..">", self:Parent(), "auto_PC_EVENT_ID", self.ModuleContext, self.RobotContext)
            self.AssignedParam = toHandle
        end

        if typeCheckOk ~= true then 
            ag_utils.log("Parameter type mismatch: ", self, toHandle) 
            error(".")
            return
        end
        -- ag_utils.log(toHandle)
        if toHandle:EntityType() == "Parameter" then
            if toHandle.Type == "Expression" then
                for _, tk in ipairs(toHandle.Value) do
                    if tk.param_id ~= nil then 
                        local depParam = toHandle:Parent():ResolvePath(tk.param_id)
                        if depParam == nil then
                            ag_utils.log("Unresolved path in expression", tk.param_id)
                            error(".")
                        else
                            local tokenParamToHandle = depParam.AssignedParam or depParam
                            -- TODO need to create module context method to easily retrieve constants
                            if (tokenParamToHandle.Type == "Integer" or tokenParamToHandle.Type == "Float" or tokenParamToHandle.Type == "Vector"or tokenParamToHandle.Type == "ByteString") then
                                tokenParamToHandle:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
                                local numericConstantResolvedParam 
                                
                                if tokenParamToHandle.Mutable == true then
                                    -- ag_utils.log("Used mutable param in expression")
                                    numericConstantResolvedParam = tokenParamToHandle
                                elseif tokenParamToHandle.Type == "Float" then
                                    numericConstantResolvedParam = self.RobotContext.Entities.NumericConstantsParams[tokenParamToHandle.Value]
                                elseif tokenParamToHandle.Type == "Integer" then
                                    numericConstantResolvedParam = self.RobotContext.Entities.NumericIntegerConstantsParams[tokenParamToHandle.Value]
                                elseif tokenParamToHandle.Type == "Vector" then
                                    numericConstantResolvedParam = self.RobotContext.Entities.VectorConstantsParams[tostring(tokenParamToHandle.Value)]
                                    -- ag_utils.log("HERE", numericConstantResolvedParam)
                                elseif tokenParamToHandle.Type == "ByteString" then
                                    numericConstantResolvedParam = self.RobotContext.Entities.StringConstantsParams[tokenParamToHandle.Value]
                                end
                                
                                if numericConstantResolvedParam == nil then
                                    error("here")
                                end

                                tk.actiongraphParam = numericConstantResolvedParam
                                -- ag_utils.log("HERE")
                            else
                                tk.actiongraphParam = tokenParamToHandle
                                tk.actiongraphParam:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
    
                            end
                        end
                    elseif tk.numeric_value ~= nil then
                        local ncName = "__numericConstantParam"..tk.numeric_value
                        if self.RobotContext.Entities.NumericConstantsParams[tk.numeric_value] == nil then
                            self.RobotContext.Entities.NumericConstantsParams[tk.numeric_value] = 
                                CreateParam(tk.numeric_value, nil, ncName, self.ModuleContext, self.RobotContext)
                        end
                        tk.actiongraphParam = self.RobotContext.Entities.NumericConstantsParams[tk.numeric_value]
                        tk.actiongraphParam:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
                    
                    elseif tk.vector_value ~= nil then
                        local ncName = "__vectorConstantParam"..tostring(tk.vector_value)
                        if self.RobotContext.Entities.VectorConstantsParams[tostring(tk.vector_value)] == nil then
                            self.RobotContext.Entities.VectorConstantsParams[tostring(tk.vector_value)] = 
                                CreateParam({tk.vector_value[1], tk.vector_value[2], tk.vector_value[3]}, nil, ncName, self.ModuleContext, self.RobotContext)
                        end

                        tk.actiongraphParam = self.RobotContext.Entities.VectorConstantsParams[tostring(tk.vector_value)]
                        tk.actiongraphParam:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)

                    elseif tk.string_value ~= nil then
                        local ncName = "__stringConstantParam"..tk.string_value
                        if self.RobotContext.Entities.StringConstantsParams[tk.string_value] == nil then
                            self.RobotContext.Entities.StringConstantsParams[tk.string_value] = 
                                CreateParam(string.format("/%s/", tk.string_value), nil, ncName, self.ModuleContext, self.RobotContext)
                        end

                        tk.actiongraphParam = self.RobotContext.Entities.StringConstantsParams[tk.string_value]
                        tk.actiongraphParam:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
                    end
                end
            elseif toHandle.Type == "PC_EVENT_ID" then
                -- ag_utils.log("here")
                if self:Parent():EntityType() ~= "Graph" then 
                    error("here")
                end

                if self:Parent().IsPCEventEmitter == true then 
                    toHandle.RobotContext:RegisterPCEvent(toHandle)
                end

                if self:Parent().IsPCEventWaiter == true then  
                    toHandle.RobotContext:RegisterPCtoRobotEvent(toHandle)
                end
            elseif self.Type == "Float" and (toHandle.Type == "Float" or toHandle.Type == "Integer") then
                if toHandle.Mutable ~= true then
                    if type(toHandle.Value) ~= "number" then 
                        error("Expected number value for parameter "..toHandle:ID())
                    end
                    local ncName = "__numericConstantParam"..toHandle.Value
                    if self.RobotContext.Entities.NumericConstantsParams[toHandle.Value] == nil then
                        self.RobotContext.Entities.NumericConstantsParams[toHandle.Value] = 
                            CreateParam(toHandle.Value, nil, ncName, self.ModuleContext, self.RobotContext)
                        -- ag_utils.log("CREATED NEW NUMERIC CONSTANT PARAM ", self.RobotContext.Entities.NumericConstantsParams[toHandle.Value])
                    end
                    toHandle = self.RobotContext.Entities.NumericConstantsParams[toHandle.Value]
                else
                    -- toHandle.RobotContext:RegisterMutableParam(toHandle)
                end
            elseif self.Type == "Integer" and (toHandle.Type == "Integer" or toHandle.Type == "Float") then
                if toHandle.Mutable ~= true then
                    if type(toHandle.Value) ~= "number" then 
                        ag_utils.actionGraphSrcKeyError(src, 'Type', "Expected number value for parameter")
                        error("Expected number value for parameter "..toHandle:ID())
                    end
                    local ncName = "__integerNumericConstantParam"..toHandle.Value
                    if self.RobotContext.Entities.NumericIntegerConstantsParams[toHandle.Value] == nil then
                        self.RobotContext.Entities.NumericIntegerConstantsParams[toHandle.Value] = 
                            CreateParam({Type = "Integer", Value=toHandle.Value}, nil, ncName, self.ModuleContext, self.RobotContext)
                        -- ag_utils.log("CREATED NEW INTEGER NUMERIC CONSTANT PARAM ", self.RobotContext.Entities.NumericIntegerConstantsParams[toHandle.Value])
                    end
                    toHandle = self.RobotContext.Entities.NumericIntegerConstantsParams[toHandle.Value]
                else
                    -- toHandle.RobotContext:RegisterMutableParam(toHandle)
                end
            elseif self.Type == "Vector" and toHandle.Type == "Vector" then
                if toHandle.Mutable ~= true then
                    if getmetatable(toHandle.Value) ~= require'vector' then 
                        error("Expected vector value for parameter "..toHandle:ID())
                    end
                    -- ag_utils.log("HERE", toHandle.Value)
                    local ncName = "__vectorConstantParam"..tostring(toHandle.Value)
                    -- ag_utils.log("Vector param handling", ncName, toHandle)
                    if self.RobotContext.Entities.VectorConstantsParams[tostring(toHandle.Value)] == nil then
                        self.RobotContext.Entities.VectorConstantsParams[tostring(toHandle.Value)] = 
                            CreateParam({toHandle.Value[1], toHandle.Value[2], toHandle.Value[3]}, nil, ncName, self.ModuleContext, self.RobotContext)
                        -- ag_utils.log("CREATED NEW NUMERIC CONSTANT PARAM ", self.RobotContext.Entities.NumericConstantsParams[toHandle.Value])
                    end
                    toHandle = self.RobotContext.Entities.VectorConstantsParams[tostring(toHandle.Value)]
                else
                    -- toHandle.RobotContext:RegisterMutableParam(toHandle)
                end
            elseif self.Type == "ByteString" and toHandle.Type == "ByteString" then
                if toHandle.Mutable ~= true then
                    if type(toHandle.Value) ~= "string" then
                        error("Expected string value for parameter "..toHandle:ID())
                    end
                    -- ag_utils.log("HERE", toHandle.Value)
                    local ncName = "__stringConstantParam"..tostring(toHandle.Value)
                    -- ag_utils.log("Vector param handling", ncName, toHandle)
                    if self.RobotContext.Entities.StringConstantsParams[toHandle.Value] == nil then
                        self.RobotContext.Entities.StringConstantsParams[toHandle.Value] = 
                            CreateParam(string.format("/%s/", toHandle.Value), nil, ncName, self.ModuleContext, self.RobotContext)
                        -- ag_utils.log("CREATED NEW NUMERIC CONSTANT PARAM ", self.RobotContext.Entities.NumericConstantsParams[toHandle.Value])
                    end
                    toHandle = self.RobotContext.Entities.StringConstantsParams[toHandle.Value]
                else
                    -- toHandle.RobotContext:RegisterMutableParam(toHandle)
                end
            elseif self.Type == "ANY_LOWLEVEL" and (toHandle.Type == "Vector" or toHandle.Type == "Integer" or toHandle.Type == "Float"or toHandle.Type == "ByteString") then
                -- if toHandle.Mutable ~= true then
                --     ag_utils.log("Unexpected", self, toHandle)
                -- end
            else
                ag_utils.log(self)
                ag_utils.log(toHandle)
                utils.errorExt("Unexpected", self:Parent(), toHandle:Parent(), toHandle==self)
            end
            if alreadyVisited[toHandle] ~= true then
                visitor(toHandle, self.Type, toHandle == self)
                alreadyVisited[toHandle] = true
            end
        elseif toHandle:EntityType() == "HWModule" then
            -- log("here")
            toHandle:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
        else
            ag_utils.log("Unexpected")
        end       
    end

    local ret = ag_utils.Entity:new(param, function() return "Parameter" end, function(s, id) return s.RobotContext:GlobalEntity(id) end)
   
    return ret
end
