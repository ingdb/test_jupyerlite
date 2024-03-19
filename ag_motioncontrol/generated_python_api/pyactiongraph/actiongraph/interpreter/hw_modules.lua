local ag_utils = require'interpreter.helpers'
local OrderedTable = require"orderedtable"
local log = ag_utils.log
log = function(a)end
local json = require'json'

function resolveHWType(typeRawData, newTypeName, typeModuleContext)

    return function(module_context, name, parentModule, robotContext)
        -- log("Instantiating ", newTypeName)
        if type(typeRawData) == "string" then
            typeRawData = {Type = typeRawData}
        end

        if type(typeRawData) ~= "table" then 
            log(json.stringify(typeRawData))
            error("Unexpected") 
        end

        if typeRawData.Type ~= nil then
            -- log("Type alias")
            -- error("unexpected")
            local Constructor = typeModuleContext:resolveType('Hardware', typeRawData.Type)
            if Constructor == nil then
                return ag_utils.actionGraphSrcValueError(typeRawData, 'Type', "Unresolved Hardware type")
            end
            local th = Constructor(module_context, name, parentModule, robotContext)
            th.TypeAlias = newTypeName
            th.Configuration:assignParams(NewConfiguration(typeRawData.Parameters, th, "anonymous_config_to_assign", module_context, robotContext))

            return th
        end

        local hwModule = {
            ModuleContext = module_context,
            TypeModuleContext = typeModuleContext,
            ChildrenModules = OrderedTable(),
            id = name,
            Type = newTypeName,
            ParentModule = parentModule,
            RobotContext = robotContext
        }
        if typeRawData.Autostart ~= nil then
            hwModule.Autostart = typeRawData.Autostart == true
        end
        hwModule.IsBasicType = typeRawData.Embedded == true
        hwModule.OptionalParams = {}
        if typeRawData.OptionalParams ~= nil then
            for _, v in ipairs(typeRawData.OptionalParams) do
                hwModule.OptionalParams[v] = true
            end
        end

        if typeRawData.Modules ~= nil then 
            for childName, childSrc in pairs(typeRawData.Modules) do
                if type(childSrc) == "string" then
                    childSrc = {Type = childSrc}
                end
        
                if childSrc.Type == nil then 
                    error("Bad HW definition")
                end
                local childConstructor = typeModuleContext:resolveType('Hardware', childSrc.Type)
                if childConstructor == nil then 
                    -- todo
                    return error("Unresolved hw type ".. childSrc.Type)
                end

                local ch = childConstructor(hwModule.ModuleContext, childName, hwModule, robotContext)
                hwModule.ChildrenModules[childName] = ch

                ch.Configuration:assignParams(NewConfiguration(childSrc.Parameters, ch, "anonymous_config_to_assign", module_context, robotContext))

                if childSrc.Autostart ~= nil then
                    ch.Autostart = childSrc.Autostart == true
                end
            end
        end

        if typeRawData.Main ~= nil then
            if hwModule.ChildrenModules[typeRawData.Main] == nil then error("cannot find child "..typeRawData.Main) end
            hwModule.MainModuleID = typeRawData.Main
        end
     
        hwModule.Configuration = NewConfiguration(typeRawData.Parameters, hwModule, "type_params", module_context, robotContext)
      
        function hwModule:GetMainBasicModule()
            if self.IsBasicType == true then return self end
            if self.MainModuleID == nil or self.ChildrenModules[self.MainModuleID] == nil then
                return nil
            end
            return self.ChildrenModules[self.MainModuleID]:GetMainBasicModule()
        end


        function hwModule:ToString()
            return string.format( "Type: %s IsBasicType: %s" , self.Type, self.IsBasicType)
        end
        function hwModule:ID()
            return self.id
        end

        function hwModule:Children()
            local r = OrderedTable()
            for k, v in pairs(self.ChildrenModules) do 
                r[k] = v
            end
            for k, v in pairs(self.Configuration.Parameters) do 
                r[k] = v
            end
            return r
        end
        function hwModule:Parent()
            return self.ParentModule
        end

        function hwModule:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
            local alreadyVisited = alreadyVisited or {}
    
          
            if self.IsBasicType == true then
                local paramMap = {}

                for prmID, v in pairs(self.Configuration.Parameters) do
                    local skipIt = false
                    if v.AssignedParam == nil and v.Value == nil then
                        if self.OptionalParams[v:ID()] == true then 
                            -- ag_utils.log("Param is skipped, because it is optional: ", v)
                            skipIt = true
                        else
                            ag_utils.log("Param not set: ", v)
                            ag_utils.log(typeRawData.Parameters[prmID])
                            ag_utils.actionGraphSrcKeyError(typeRawData.Parameters, prmID, "Expected number value for parameter")
                            -- ag_utils.actionGraphSrcValueError(src, events, "Required parameter not set") --TODO
                        end
                    end
                    if v:GetFinalAssignedEntity() == nil and self.OptionalParams[v:ID()] == true then
                        -- ag_utils.log("Skipping optional unresolved param: ", v)
                        skipIt = true
                    end
                    if skipIt == false then
                        v:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)

                        local toHandle =  v:GetFinalAssignedEntity()

                        if toHandle == nil then 
                            ag_utils.log("Unresolved: ", v) 
                            return error(".")
                        end

                        -- TODO add Vector type below
                        if toHandle.Mutable == false then -- Why not mutable?
                            if v.Type == "Float" and (toHandle.Type == "Float" or toHandle.Type == "Integer")  then
                                if self.RobotContext.Entities.NumericConstantsParams[toHandle.Value] == nil then
                                    error(".")
                                end
                                toHandle = self.RobotContext.Entities.NumericConstantsParams[toHandle.Value]
                            elseif v.Type == "Integer" and (toHandle.Type == "Float" or toHandle.Type == "Integer")  then
                                if self.RobotContext.Entities.NumericIntegerConstantsParams[toHandle.Value] == nil then
                                    error(".")
                                end
                                toHandle = self.RobotContext.Entities.NumericIntegerConstantsParams[toHandle.Value]
                            elseif v.Type == "Vector" and (toHandle.Type == "Vector")  then
                                if self.RobotContext.Entities.VectorConstantsParams[tostring(toHandle.Value)] == nil then
                                    error(".")
                                end
                                toHandle = self.RobotContext.Entities.VectorConstantsParams[tostring(toHandle.Value)]
                            elseif v.Type == "ByteString" and (toHandle.Type == "ByteString")  then
                                if self.RobotContext.Entities.StringConstantsParams[toHandle.Value] == nil then
                                    error(".")
                                end
                                toHandle = self.RobotContext.Entities.StringConstantsParams[toHandle.Value]
                            else
                                -- error("unexpected")
                            end
                        end
                        paramMap[v] = toHandle
                    end
                end

                if alreadyVisited[self] ~= true then
                    visitor(self, paramMap)
                    alreadyVisited[self] = true
                end
            end
            for _, v in pairs(self.ChildrenModules) do 
                v:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
            end
        end

        return ag_utils.Entity:new(hwModule, function() return "HWModule" end, function(s, id) return s.RobotContext:GlobalEntity(id) end)

    end
end
