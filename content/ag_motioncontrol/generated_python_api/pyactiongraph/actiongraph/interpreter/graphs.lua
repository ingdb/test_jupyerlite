local ag_utils = require'interpreter.helpers'
local log = ag_utils.log
local json = require'json'
local OrderedTable = require"orderedtable"
local path_lib = require"pl.path"
local function NewStateTransitionEvent(name, parent, moduleContext, embedded, robotContext)
    -- log(name)
    local r = {
        id = name,
        Type = "StateTransitionEvent",
        ModuleContext = moduleContext,
        parentGraph = parent,
        embedded = embedded,
        RobotContext = robotContext
    }

    function r:ToString()
        return string.format( "IsEmbedded: %s, Parent: %s", self.embedded, self.parentGraph)
    end
    function r:ID()
        return self.id
    end

    function r:Children()
        local r = OrderedTable()
        return r
    end
    function r:Parent()
        return self.parentGraph
    end

    function r:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
       
    end
    return ag_utils.Entity:new(r, function() return "StateTransitionEvent" end, function(s, id) return r.RobotContext:GlobalEntity(id) end)

end

local function NewStateControlSlot(name, parent, moduleContext, embedded, robotContext)
    local r = {
        id = name,
        Type = "StateControlSlot",
        ModuleContext = moduleContext,
        parentGraph = parent,
        embedded = embedded,
        RobotContext = robotContext
    }

    function r:ToString()
        return string.format( "IsEmbedded: %s, Parent: %s", self.embedded, self.parentGraph)
    end
    function r:ID()
        return self.id
    end

    function r:Children()
        local r = OrderedTable()
        return r
    end
    function r:Parent()
        return self.parentGraph
    end

    function r:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
       
    end
    return ag_utils.Entity:new(r, function() return "StateControlSlot" end, function(s, id) return r.RobotContext:GlobalEntity(id) end)

end

function resolveGraphType(typeRawData, newTypeName, typeModuleContext)
    if typeModuleContext == nil then
        error(newTypeName)
    end
    return function(module_context, name, parentModule, isRoot, robotContext)
        -- log("Creating type ", newTypeName)

        if type(typeRawData) == "string" then
            typeRawData = {Type = typeRawData}
        end

        if type(typeRawData) ~= "table" then 
            log(json.stringify(typeRawData), newTypeName, name)
            error("Unexpected") 
        end
        if typeRawData.Type ~= nil then
            -- log("Type alias", typeRawData.Type)
            -- error("unexpected")
            Constructor = typeModuleContext:resolveType('Graphs', typeRawData.Type)
            if Constructor == nil then
                ag_utils.actionGraphSrcValueError(typeRawData, 'Type', "Unresolved Graph type")
            end
            local th = Constructor(module_context, name, parentModule, isRoot, robotContext)
            th.TypeAlias = newTypeName
            th.Configuration:assignParams(NewConfiguration(typeRawData.Parameters, th, "anonymous_config_to_assign", module_context, robotContext))
            if th.IsPCEventEmitter then
                if typeRawData.IgnoreUnhandledEvent == true then
                    th.IgnoreUnhandledEvent = true
                end
            end
            if typeRawData.Script then
                th.Script = typeRawData.Script
            end
            return th
        end
        local graph = {
            ModuleContext = module_context,
            TypeModuleContext = typeModuleContext,
            RobotContext = robotContext,
            ChildrenGraphs = OrderedTable(),
            id = name,
            Type = newTypeName,
            ParentModule = parentModule,
            Connections = {}
        }
        graph.Script = typeRawData.Script
        graph.IsBasicType = typeRawData.Embedded == true
        graph.OptionalParams = {}
        if typeRawData.OptionalParams ~= nil then
            for _, v in ipairs(typeRawData.OptionalParams) do
                graph.OptionalParams[v] = true
            end
        end

        graph.IsPCEventEmitter = typeRawData.IsPCEventEmitter ==true and graph.IsBasicType
        graph.IsPCEventWaiter = typeRawData.IsPCEventWaiter == true and graph.IsBasicType

        if (typeRawData.Parallel ~= nil or typeRawData.Sequential ~= nil) and typeRawData.Nodes ~= nil then
            ag_utils.actionGraphSrcKeyError(typeRawData, 'Nodes', "'Parallel' and 'Sequential' blocks cannot be used with 'Nodes' block")
        end

        if typeRawData.Parallel ~= nil then 
            graph.Type = newTypeName
            graph.TypeAlias = string.format("%s(PARALLEL)", newTypeName)
            local childrenStartSlots = {}
            local childrenStoppedEvents = {}
            for memberIndex, memberSrcOrig in ipairs(typeRawData.Parallel) do
                local childConstructor

                local memberSrc = memberSrcOrig
                if type(memberSrcOrig) == "string" then
                    memberSrc = {Type = memberSrcOrig}
                end


                if memberSrc.Type ~= nil then
                    childConstructor = typeModuleContext:resolveType('Graphs', memberSrc.Type)
                    if childConstructor == nil then 
                        ag_utils.actionGraphSrcValueError(typeRawData.Parallel, memberIndex, "Unresolved Graph type")
                    end
                else
                    -- log("recursive from parallel")
                    -- log(memberSrc)
                    childConstructor = resolveGraphType(memberSrc, graph.Type.."_P"..memberIndex, typeModuleContext)
                    if childConstructor == nil then 
                        error("Unresolved graph type PARALLEL_SIBLING_AUTO_TYPE")
                    end
                end
               
                local name = tostring(memberIndex)
                local ch = childConstructor(graph.ModuleContext, name, graph, false, graph.RobotContext)
                ch.Configuration:assignParams(NewConfiguration(memberSrc.Parameters, ch, "anonymous_config_to_assign", module_context, graph.RobotContext))
                if ch.IsPCEventEmitter then
                    if memberSrcOrig.IgnoreUnhandledEvent == true then
                        ch.IgnoreUnhandledEvent = true
                    end
                end
                if memberSrcOrig.Script then
                    ch.Script = memberSrcOrig.Script
                end
                graph.ChildrenGraphs[name] = ch
                -- log(memberIndex, ch)

                table.insert(childrenStartSlots, "."..name..".start")
                table.insert(childrenStoppedEvents, "."..name..".stopped")
            end

            table.insert(graph.Connections, {
                When = {".started"},
                What = childrenStartSlots,
                isAny = false
            })
            table.insert(graph.Connections, {
                When = childrenStoppedEvents,
                What = {".stop"},
                isAny = false
            })

            -- error("Not implemented")
        end
        if typeRawData.Sequential ~= nil then 
            graph.Type = newTypeName
            graph.TypeAlias = string.format("%s(SEQUENTIAL)", newTypeName)
            local prevSiblingName
            for memberIndex, memberSrcOrig in ipairs(typeRawData.Sequential) do
                local memberSrc = memberSrcOrig
                if type(memberSrcOrig) == "string" then
                    memberSrc = {Type = memberSrcOrig}
                end

                local childConstructor
                if memberSrc.Type ~= nil then
                    childConstructor = typeModuleContext:resolveType('Graphs', memberSrc.Type)
                    if childConstructor == nil then 
                        -- todo
                        ag_utils.actionGraphSrcValueError(typeRawData.Sequential, memberIndex, "Unresolved Graph type")
                    end
                else
                    -- log("recursive from sequential")
                    -- log(memberSrc)
                    childConstructor = resolveGraphType(memberSrc, graph.Type.."_S"..memberIndex, typeModuleContext)
                    if childConstructor == nil then 
                        error("Unresolved graph type SEQUENCIAL_SIBLING_AUTO_TYPE")
                    end
                end
             
                local name = tostring(memberIndex)
                local ch = childConstructor(graph.ModuleContext, name, graph, false, graph.RobotContext)
                ch.Configuration:assignParams(NewConfiguration(memberSrc.Parameters, ch, "anonymous_config_to_assign", module_context, graph.RobotContext))
                if ch.IsPCEventEmitter then
                    if memberSrcOrig.IgnoreUnhandledEvent == true then
                        ch.IgnoreUnhandledEvent = true
                    end
                end
                if memberSrcOrig.Script then
                    ch.Script = memberSrcOrig.Script
                end
                graph.ChildrenGraphs[name] = ch
                -- log(memberIndex, ch)

                if memberIndex == 1 then
                    table.insert(graph.Connections, {
                        When = {".started"},
                        What = {"."..name..".start"},
                        isAny = true
                    })
                end

                if memberIndex == #typeRawData.Sequential then
                    table.insert(graph.Connections, {
                        When = {"."..name..".stopped"},
                        What = {".stop"},
                        isAny = true
                    })
                end

                if prevSiblingName ~= nil then
                    table.insert(graph.Connections, {
                        When = {"."..prevSiblingName..".stopped"},
                        What = {"."..name..".start"},
                        isAny = true
                    })
                end
                prevSiblingName = name
            end
            -- error("Not implemented")
        end

        if typeRawData.Nodes ~= nil then 
            for childName, childSrcOrig in pairs(typeRawData.Nodes) do
                local childConstructor
                local childSrc = childSrcOrig
                if type(childSrcOrig) == "string" then
                    childSrc = {Type = childSrcOrig}
                end
                if childSrc.Type == nil then 
                    childConstructor = resolveGraphType(childSrc, "ANONIMOUS_TYPE", typeModuleContext)
                else
                    childConstructor = typeModuleContext:resolveType('Graphs', childSrc.Type)
                end
                if childConstructor == nil then 
                    -- todo
                    if childSrcOrig.Type ~= nil then
                        ag_utils.actionGraphSrcValueError(childSrcOrig, 'Type', "Unresolved Graph type")
                    else
                        ag_utils.actionGraphSrcValueError(typeRawData.Nodes, childName, "Unresolved Graph type")
                    end
                end

                local ch = childConstructor(graph.ModuleContext, childName, graph, false, graph.RobotContext)
                graph.ChildrenGraphs[childName] = ch

                ch.Configuration:assignParams(NewConfiguration(childSrc.Parameters, ch, "anonymous_config_to_assign", module_context, graph.RobotContext))
                if ch.IsPCEventEmitter then
                    if childSrcOrig.IgnoreUnhandledEvent == true then
                        ch.IgnoreUnhandledEvent = true
                    end
                end
                if childSrcOrig.Script then
                    ch.Script = childSrcOrig.Script
                end
                ch:AddConnections(childSrc.Connections)
            end
        end
        graph.IsRootGraph = isRoot == true
        if graph.IsBasicType == false then
            local childConstructor = typeModuleContext:resolveType('Graphs', "SYNCER") -- TODO REMOVE HARDCODE
            if childConstructor == nil then 
                -- todo
                error("Unresolved graph type SYNCER")
            end

            local ch = childConstructor(graph.ModuleContext, "__syncer", graph, graph.IsRootGraph, graph.RobotContext)
            graph.SyncerNode = ch
        end

        graph.StateTransitionEvents = {}
        graph.StateControlSlots = {}
        

        if typeRawData.StateTransitionEvents ~= nil then 
            for id, dt in pairs(typeRawData.StateTransitionEvents) do
                
                if dt == ag_utils.SRC_NULL then -- TODO error handling
                    graph.StateTransitionEvents[id] = NewStateTransitionEvent(id, graph, module_context, false, graph.RobotContext)
                else
                    log("Unsupported StateTransitionEvent")
                end
            end
        end
        if typeRawData.StateControlSlots ~= nil then
            for id, dt in pairs(typeRawData.StateControlSlots) do
                if dt == ag_utils.SRC_NULL then -- TODO error handling
                    graph.StateControlSlots[id] = NewStateControlSlot(id, graph, module_context, false, graph.RobotContext)
                else
                    log("Unsupported StateTransitionEvent")
                end
            end
        end

        graph.StateTransitionEvents.started = NewStateTransitionEvent("started", graph, module_context, true, graph.RobotContext)
        graph.StateTransitionEvents.stopped = NewStateTransitionEvent("stopped", graph, module_context, true, graph.RobotContext)
        graph.StateTransitionEvents.erred = NewStateTransitionEvent("erred", graph, module_context, true, graph.RobotContext)

        graph.StateControlSlots.start = NewStateControlSlot("start", graph, module_context, true, graph.RobotContext)
        graph.StateControlSlots.stop = NewStateControlSlot("stop", graph, module_context, true, graph.RobotContext)
        graph.StateControlSlots.cancel = NewStateControlSlot("cancel", graph, module_context, true, graph.RobotContext)

            
        function graph:AddConnections(src)
            if src == nil then return end
            for events, slots in pairs(src) do
                -- log("Connection")
                local When = {}
                local What = {}
                local isAny = false
                if type(events) == "string" then
                    
                    if self:ResolvePath(events) == nil then
                        ag_utils.actionGraphSrcKeyError(src, events, "Unresolved event")
                    end
                    table.insert( When, events )
                    -- log("\tEvent", events)
                elseif type(events) == "table" then
                    if events.All ~= nil and events.Any ~= nil then 
                        ag_utils.actionGraphSrcKeyError(src, events, "Bad syntax in connection declaration")
                    end
                    if events.All == nil and events.Any == nil then
                        ag_utils.actionGraphSrcKeyError(src, events, "Bad syntax in connection declaration")
                    end
                    isAny = events.Any ~= nil

                    for eventIndex, event in ipairs(events.All or events.Any) do
                        if self:ResolvePath(event) == nil then
                            ag_utils.actionGraphSrcValueError(events.All or events.Any, eventIndex, "Unresolved event")
                        end
                        table.insert( When, event )
                        
                    end
                else
                    ag_utils.actionGraphSrcKeyError(src, events, "Bad syntax in connection declaration")
                end
                -- log("\tIs any event:", isAny)
               
                if type(slots) == "string" then
                    if self:ResolvePath(slots) == nil then
                        ag_utils.actionGraphSrcValueError(src, events, "Unresolved slot")
                    end
                    table.insert( What, slots )
                    -- log("\tSlot", slots)
                elseif type(slots) == "table" then
                    if #slots == 0 then 
                        ag_utils.actionGraphSrcValueError(src, events, "Empty slot")
                    end
                    for slotIndex, slot in ipairs(slots) do
                        if self:ResolvePath(slot) == nil then
                            ag_utils.actionGraphSrcValueError(slots, slotIndex, "Unresolved slot")
                        end
                        table.insert( What, slot )
                        -- log("\tSlot", slot)
                    end
                else
                    ag_utils.actionGraphSrcValueError(src, events, "Bad syntax in connection declaration")
                end

                table.insert(self.Connections, {
                    When = When,
                    What = What,
                    isAny = isAny
                })
            end
        end
        graph = ag_utils.Entity:new(graph, function() return "Graph" end, function(s, id) return s.RobotContext:GlobalEntity(id) end)
    
        function graph:ToString()
            return string.format( "Type: %s IsBasicType: %s IsRoot: %s" , self.Type, self.IsBasicType, self.IsRootGraph)
        end
        function graph:ID()
            return self.id
        end

        function graph:Children()
            local r = OrderedTable()
            for k, v in pairs(self.ChildrenGraphs) do 
                r[k] = v
            end

            for k, v in pairs(self.Configuration.Parameters) do 
                r[k] = v
            end

            for k, v in pairs(self.StateTransitionEvents) do 
                r[k] = v
            end

            for k, v in pairs(self.StateControlSlots) do 
                r[k] = v
            end

            return r
        end
        function graph:Parent()
            return self.ParentModule
        end

        graph.Configuration = NewConfiguration(typeRawData.Parameters, graph, "type_params", module_context, graph.RobotContext)

        graph:AddConnections(typeRawData.Connections)



        function graph:GatherThisConnections()
            local list = {}
        end
        function graph:GatherConnections()
            local list = {}

            for _, v in pairs(self.ChildrenGraphs) do 
                local conns = v:GatherConnections()
                for _, conn in ipairs(conns) do
                    table.insert( list, conn )
                end
            end
            for _, conn in ipairs(self.Connections) do
                local resolvedEvents = {}
                local resolvedSlots = {}
                for _, event in ipairs(conn.When) do
                    local eventObj = self:ResolvePath(event)
                    if eventObj == nil then 
                        error("unresolved event " .. event .. " "..tostring(self))
                    end
                    table.insert(resolvedEvents, eventObj)
                    -- log(eventObj)
                end
                for _, slot in ipairs(conn.What) do
                    local slotObj = self:ResolvePath(slot)
                    if slotObj == nil then 
                        error("unresolved slot " .. slot .. " "..tostring(self))
                    end
                    table.insert(resolvedSlots, slotObj)
                    -- log(slotObj)
                end
                local r = {
                    IsAnyEvent = conn.isAny,
                    ResolvedEvents = resolvedEvents,
                    ResolvedSlots = resolvedSlots
                }
                function r:print()
                    log("Connection")
                    log("  IsAnyEvent", self.IsAnyEvent)
                    log("  Events")
                    for _, vv in ipairs(self.ResolvedEvents) do
                        log("    ", vv)
                    end
                    log("  Slots")
                    for _, vv in ipairs(self.ResolvedSlots) do
                        log("    ", vv)
                    end
                end
                table.insert( list,  r)
            end
            return list
        end

        function graph:FindSlotOrEventReasonsList(connections, e)
            -- returns disjunctive list of conjuction groups
            
            if e:EntityType()== "StateTransitionEvent" and e.embedded == true then
                return {e}
            end
            local ret = {}
            for _, conn in ipairs(connections) do
                for _, target in ipairs(conn.ResolvedSlots) do
                    if target == e then
                       
                        if conn.IsAnyEvent == true or #conn.ResolvedEvents == 1 then
                            for _, when in ipairs(conn.ResolvedEvents) do
                                local resolvedWhen = self:FindSlotOrEventReasonsList(connections, when)
                                for _, when2 in ipairs(resolvedWhen) do
                                    table.insert( ret, when2 )
                                end
                            end
    
                        else
                            local conj = {}
                            for _, when in ipairs(conn.ResolvedEvents) do
                               
                                local resolvedWhen = self:FindSlotOrEventReasonsList(connections, when)
                                if #resolvedWhen ~= 1 or resolvedWhen[1]:EntityType() ~= "StateTransitionEvent" or resolvedWhen[1].embedded ~= true then
                                    error("Complex Conjuctions are not implemented yet")
                                end
                                table.insert(conj, resolvedWhen[1])
                               
                            end
                            if #conj == 0 then error("empty conjuction group") end
                            table.insert( ret, conj )
                        end
                    end
                end
            end

            return ret
        end

        function graph:GroupConnectionsByEventsAndSlots(connections)
            local ret = OrderedTable()
            for _, conn in ipairs(connections) do
                for _, slot in ipairs(conn.ResolvedSlots) do
                    if ret[slot] == nil then
                        if slot.embedded == true and slot:EntityType() == "StateControlSlot" then
                            ret[slot] = self:FindSlotOrEventReasonsList(connections, slot)
                        end
                    end
                end
            end

            return ret
        end


        function graph:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited, dontGatherConnections)
            local alreadyVisited = alreadyVisited or {}
    
            for _, v in pairs(self.ChildrenGraphs) do 
                v:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited, true)
            end

            if self.IsBasicType == true then
                local paramMap = {}
                for prmID, v in pairs(self.Configuration.Parameters) do 
                    local skipIt = false
                    if v.AssignedParam == nil and v.Value == nil and v.Type ~= "PC_EVENT_ID" then
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

                        -- TODO Needed??
                        v:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)

                        -- ag_utils.log(v)
                        local toHandle = v:GetFinalAssignedEntity()
                        if toHandle == nil then 
                            ag_utils.log("Unresolved: ", v) 
                            error(".")
                        end

                        if v.Mutable == true and toHandle.Mutable ~= true then
                            ag_utils.log("Immutable param", toHandle, "cannot be assigned to mutable param", v)
                            error(".")
                        end
                        -- TODO Needed??
                        -- toHandle:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
                        if v.Type == "Float" and (toHandle.Type == "Float" or toHandle.Type == "Integer") then
                            -- ag_utils.log(toHandle)
                            if toHandle.Mutable == false then
                                if self.RobotContext.Entities.NumericConstantsParams[toHandle.Value] == nil then
                                    error(".")
                                end
                                toHandle = self.RobotContext.Entities.NumericConstantsParams[toHandle.Value]
                            end
                        elseif v.Type == "Integer" and (toHandle.Type == "Integer" or toHandle.Type == "Float")  then
                            if toHandle.Mutable == false then
                                if self.RobotContext.Entities.NumericIntegerConstantsParams[toHandle.Value] == nil then
                                    error(".")
                                end
                                toHandle = self.RobotContext.Entities.NumericIntegerConstantsParams[toHandle.Value]
                            end
                        elseif v.Type == "Vector" and (toHandle.Type == "Vector")  then
                            if toHandle.Mutable == false then
                                -- ag_utils.log("HERE")
                                if self.RobotContext.Entities.VectorConstantsParams[tostring(toHandle.Value)] == nil then
                                    error(".")
                                end
                                toHandle = self.RobotContext.Entities.VectorConstantsParams[tostring(toHandle.Value)]
                            end
                        elseif v.Type == "ByteString" and (toHandle.Type == "ByteString")  then
                            if toHandle.Mutable == false then
                                -- ag_utils.log("HERE")
                                if self.RobotContext.Entities.StringConstantsParams[toHandle.Value] == nil then
                                    error(".")
                                end
                                toHandle = self.RobotContext.Entities.StringConstantsParams[toHandle.Value]
                            end
                        else
                            -- ag_utils.log(toHandle)

                            -- error("unexpected")
                        end

                        paramMap[v] = toHandle
                    end
                end

                if alreadyVisited[self] ~= true then
                    visitor(self, paramMap)
                    alreadyVisited[self] = true
                end
            end
            

            if self.SyncerNode ~= nil then
                if alreadyVisited[self.SyncerNode] ~= true then
                    visitor(self.SyncerNode)
                    alreadyVisited[self.SyncerNode] = true
                end
            end

            if self.IsRootGraph == true then --toplevel
                local e = {
                    ToString = function(s) return s.Node:ToString() end
                }

                if self.IsBasicType == true then 
                    e.Node = self 
                else
                    e.Node = self.SyncerNode
                end

                
                visitor(ag_utils.Entity:new(e, function() return "EntryPoint" end))
            end 

            if dontGatherConnections == true then
                return
            end

            local allConnections = self:GatherConnections()          
            local groupedConnectionInfo = self:GroupConnectionsByEventsAndSlots(allConnections)
         
            -- 3) convert to embedded events-> embedded slots chains

            --[[ 
                custom event should work just like an alias param:
                embedded event -> custom event -> custom event->custom slot->custom slot->embedded slot
            --]]

            for sl, sourceEvents in pairs(groupedConnectionInfo) do 
                -- log("real slot", sl)
                if #sourceEvents == 0 then
                    -- log("  unconnected slot", sl)
                end
                local s = ""
                for _, src in ipairs(sourceEvents) do
                    local WhenList = {}

                    if src.EntityType ~= nil then
                        -- log("  ", src)
                        table.insert( WhenList, src )
                        s = s .. " " .. tostring(src)
                    else
                        -- log("  AND:")
                        for _, conjMember in ipairs(src) do
                            -- log("    ", conjMember)
                            table.insert( WhenList, conjMember )
                            s = s .. " " .. tostring(conjMember)
                        end
                    end
                    -- s = s .. " -> " .. tostring(sl)
                    local connectionEntity = {
                        When = WhenList,
                        What =  {sl}
                    }

                    function connectionEntity:ToString() 
                        return s
                    end
                    visitor(ag_utils.Entity:new(connectionEntity, function() return "Connection" end))

                end
            end
        end

        function graph:IterateUserScriptsBottomToTop(visitor)

            for _, v in pairs(self.ChildrenGraphs) do 
                v:IterateUserScriptsBottomToTop(visitor)
            end

            if self.Script ~= nil then
                local scrRelPath =  self.Script
                if not path_lib.isabs(scrRelPath) then
                    scrRelPath = path_lib.abspath(scrRelPath, self.TypeModuleContext.dir_path)
                end

                visitor(scrRelPath, self)
            end
        end
        return graph
    end
end
