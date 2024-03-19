local P = {}   -- package


local path_lib = require("pl.path")
local utils = require("utils")
local table = table
local ipairs = ipairs
local dir_lib = require("pl.dir")
local pairs = pairs
local require = require
local ag_utils = require'interpreter.helpers'
local log = ag_utils.log
local readSrc  = ag_utils.readSrc
local type = type
local error = error
local json = require'json'
local OrderedTable = require"orderedtable"
local string = string
require'interpreter.configurations'
local NewConfiguration = NewConfiguration
local scheduler = require"scheduler"
local millis = millis
local globalEnv = _ENV
local _ENV = P

function NewRobotContext (robotID, raw_structure, moduleContext) 
    local robotContext = {
        ID = robotID,
        Entities = OrderedTable(),
        src_structure = raw_structure,
        moduleContext = moduleContext,
        RegisteredEventsToSend = {},
        RegisteredEventHandlers = {},
        AvailableEventsToListen = {}
    }
    robotContext.Script = raw_structure.Script
    robotContext.Serial = raw_structure.Serial
    robotContext.Entities.Hardware  = nil
    robotContext.Entities.Configurations  = OrderedTable()
    robotContext.Entities.Graph  = nil
    robotContext.Entities.NumericConstantsParams  = OrderedTable()
    robotContext.Entities.NumericIntegerConstantsParams  = OrderedTable()
    robotContext.Entities.VectorConstantsParams  = OrderedTable()
    robotContext.Entities.StringConstantsParams  = OrderedTable()
    
    function robotContext:instantiateHardware()
        -- log("Instantiating hardware")
        local topLevelHW = self.src_structure.Hardware
        if topLevelHW == nil then return end

        local HWType
        local HWParams

        if type(topLevelHW) == "string" then
            HWType = topLevelHW
        elseif type(topLevelHW) == "table" then
            HWType = topLevelHW.Type
            HWParams = topLevelHW.Parameters
        else
            error("unexpected")
        end

        -- log("Instantiating root hw module", topLevelHWID)
        local constructor = self.moduleContext:resolveType('Hardware', HWType)
        if constructor == nil then 
            -- todo
            return error("Unresolved hw type ".. (topLevelHW.Type or "nil"))
        end

        local newHW = constructor(self.moduleContext, "__root_hardware", nil, self)
    
        if HWParams~= nil then
            newHW.Configuration:assignParams(NewConfiguration(HWParams, newHW, "anonymous_config_to_assign", self.moduleContext, self))
        end

        if topLevelHW.Autostart ~= nil then
            newHW.Autostart = topLevelHW.Autostart == true
        end

        self.Entities.Hardware = newHW

    end
    function robotContext:instantiateConfigs()
        -- log("Instantiating configurations")
        if self.src_structure.Configurations == nil then 
            return
        end
        for topLevelConfID, topLevelConfSrc in pairs(self.src_structure.Configurations) do
        
            local ConfType
            local ConfParams
            if type(topLevelConfSrc) == "string" then
                ConfType = topLevelConfSrc
            elseif type(topLevelConfSrc) == "table" then
                ConfType = topLevelConfSrc.Type
                ConfParams = topLevelConfSrc.Parameters
            end

            -- log("Instantiating root config module", topLevelConfID)
            local constructor = self.moduleContext:resolveType('Configurations', ConfType)
            if constructor == nil then 
                -- todo
                error("Unresolved conf type ".. ConfType)
            end

            local newConf = constructor(self.moduleContext, topLevelConfID,  self)  
        
            newConf:assignParams(NewConfiguration(ConfParams, nil, topLevelConfID, self.moduleContext, self))
            self.Entities.Configurations[topLevelConfID] = newConf

        end
    end

    function robotContext:instantiateGraphs()
        if self.src_structure.Graph == nil then
            error('No main graph selected')
        end
        local GraphType
        local GraphParams

        if type(self.src_structure.Graph) == "string" then
            GraphType = self.src_structure.Graph
        elseif type(self.src_structure.Graph) == "table" then
            GraphType = self.src_structure.Graph.Type
            GraphParams = self.src_structure.Graph.Parameters
        end
        local constructor = self.moduleContext:resolveType('Graphs', GraphType)
        if constructor == nil then
            -- todo
            error("Unresolved graph type ".. (GraphType or "nil"))
        end
        local gr = constructor(self.moduleContext, "__root_graph", nil, true, self)
        gr.IsRootGraph = true
        if GraphParams ~= nil then
            gr.Configuration:assignParams(NewConfiguration(GraphParams, gr, "anonymous_config_to_assign", self.moduleContext, self))
        end
        self.Entities.Graph = gr
    end
    function robotContext:GlobalEntity(id)
        -- log(id)
        local whereToSearch = self.Entities
        if id ~= "Graph" and id ~= "Hardware" then
            whereToSearch = self.Entities.Configurations
        end
        local r = whereToSearch[id]
        if r == nil then 
            -- log("Unknown global entity: ", id)
        end
        return r
    end


    function robotContext:IterateAllEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
        local visited = alreadyVisited or {}
        for cName, c in pairs(self.Entities.Configurations) do
            self:IterateEmbeddedEntitiesDependencyTreeBottomToTop(cName, visitor, visited)
        end
        self:IterateEmbeddedEntitiesDependencyTreeBottomToTop("Hardware", visitor, visited)
        self:IterateEmbeddedEntitiesDependencyTreeBottomToTop("Graph", visitor, visited)
        
    end

    function robotContext:IterateEmbeddedEntitiesDependencyTreeBottomToTop(path, visitor, visited)
        local alreadyVisited = visited or {}

        local stubEntity = ag_utils.Entity:new({}, function() return "" end, function(s, id) return self:GlobalEntity(id) end)
        local root = stubEntity:ResolvePath(path)
        if root == nil then 
            -- log("path ", path, " unresolved")
        else
            root:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
        end
    end

    function robotContext:IterateUserScriptsBottomToTop(visitor)
        local stubEntity = ag_utils.Entity:new({}, function() return "" end, function(s, id) return self:GlobalEntity(id) end)
        local root = stubEntity:ResolvePath("Graph")
        if root == nil then 
            return
        else
            root:IterateUserScriptsBottomToTop(visitor)
            if self.Script then
                local scrRelPath =  self.Script
                if not path_lib.isabs(scrRelPath) then
                    scrRelPath = path_lib.abspath(scrRelPath, self.moduleContext.dir_path)
                end

                visitor(self.Script, nil)
            end
        end
    end

    function robotContext:IterateLogicalEntityChildren(ent, visitor, filterType)
        for k, v in pairs(ent:Children()) do
            if filterType == nil or v:EntityType() == filterType then 
                visitor(v)
            end
        end

    end

    function robotContext:RegisterPCEvent(paramID)
        -- log("Registered robot to PC event:", paramID, paramID:Parent())
        if paramID.Type ~= "PC_EVENT_ID" then
            error("Param is not the PC_EVENT_ID type")
        end
        
        if paramID:Parent():EntityType() ~= "Graph" then
            error("RegisterPCEvent param's parent is not the node")
        end
        if paramID:Parent().IsPCEventEmitter ~= true then
            -- log("RegisterPCEvent param's parent doesnt emitting events")
        end
        paramID.EventHandler = function(entity, ...)
            self:PCEventSharedHandler(entity, paramID, paramID.Value, ...)
        end
        -- log(paramID)
        self.AvailableEventsToListen[paramID.Value] = {}
    end

    function robotContext:SendNamedEvent(id)

        if self.RegisteredEventsToSend[id] == nil then
            log("Unknown event ", id)
            return
        end
        if type(self.RegisteredEventsToSend[id].SendEvent) ~= "function" then
            error("No SendEvent member in event param")
        end
        self.RegisteredEventsToSend[id].SendEvent()
    end

    function robotContext:SendEvent(eventParamPath)
        local stubEntity = ag_utils.Entity:new({}, function() return "" end, function(s, id) return self:GlobalEntity(id) end)
        local root = stubEntity:ResolvePath(eventParamPath)
        if root == nil then
            log("No event at path "..eventParamPath)
            return
        end
        root = root.AssignedParam or root

        if root.Type == "Alias" then
            root = root:ResolvePath(".")
        end
        if root == nil then 
            log("Unresolved: ", root) 
            return
        end
        root = root.AssignedParam or root

        if root:EntityType() ~= "Parameter" then

            log("Not a param")
            return
        end

        if type(root.SendEvent) ~= "function" then
            log("No SendEvent member in event param")
            return
        end
        root.SendEvent()
    end

    function robotContext:RegisterPCtoRobotEvent(paramID)
        if paramID.Type ~= "PC_EVENT_ID" then
            error("Param is not the PC_EVENT_ID type")
        end
        
        -- if paramID:Parent():EntityType() ~= "Graph" then
        --     error("RegisterPCtoRobotEvent param's parent is not the node")
        -- end
        -- if paramID:Parent().IsPCEventWaiter ~= true then
        --     log(paramID, paramID:Parent())
        --     error("RegisterPCtoRobotEvent param's parent doesnt emitting events")
        -- end

        local p = paramID.AssignedParam or paramID
        self.RegisteredEventsToSend[p.Value] = p
        -- log("Registered PC to Robot event:", paramID)

    end

    function robotContext:PCEventSharedHandler(entity, eventPrm, id, args)
        local handled = false
        if self.RegisteredEventHandlers[id] ~= nil  then
            handled = true
            for h, _ in pairs(self.RegisteredEventHandlers[id]) do
                h(args)
            end
        end
        if self.RegisteredEventHandlers[eventPrm] ~= nil  then
            handled = true
            for h, _ in pairs(self.RegisteredEventHandlers[eventPrm]) do
                h(args)
            end
        end
         
        if not handled and entity.IgnoreUnhandledEvent ~= true then
            -- local ts
            if args.ts ~= nil then args.ts = args.ts/1e6 end
            log(string.format("Received event from robot '%s': ", self.ID), id, json.stringify(args))
        end
        
    end

    function robotContext:SetNamedEventHandler(id, f)
        if self.AvailableEventsToListen[id] == nil then
            log("unknown event", id)
            return
        end
        if self.RegisteredEventHandlers[id] == nil then
            self.RegisteredEventHandlers[id] = {}
        end
        -- log("Added named event handler: ", self.ID, id)
        self.RegisteredEventHandlers[id][f] = true
    end

    function robotContext:WaitNamedEvent(id, timeout_or_event)
        if self.AvailableEventsToListen[id] == nil then
            log("unknown event", id)
            return
        end

        local ret
        local event = scheduler.NewEvent()
        local h = function(args) 
            ret = args
            event:set()
        end
        if self.RegisteredEventHandlers[id] == nil then
            self.RegisteredEventHandlers[id] = {}
        end
        -- log("Added named event handler: ", self.ID, id)
        self.RegisteredEventHandlers[id][h] = true
        local tt
       if type(timeout_or_event) == "number" then
            if timeout_or_event > 0 then 
                tt = scheduler.addTask(function()
                    scheduler.sleep(timeout_or_event)
                    event:set()
                end)
            end
        else
            tt = scheduler.addTask(function()
                timeout_or_event:wait()
                event:set()
            end)
        end
        event:wait()
        tt.cancel()
        self.RegisteredEventHandlers[id][h] = nil
        return ret
    end

    function robotContext:SetEventHandler(eventParamPath, f)
        local stubEntity = ag_utils.Entity:new({}, function() return "" end, function(s, id) return self:GlobalEntity(id) end)
        local eventParam = stubEntity:ResolvePath(eventParamPath)
        if eventParam == nil then
            log("Unresolved: ", eventParamPath)
        end
        eventParam = eventParam.AssignedParam or eventParam
        
        if eventParam.Type == "Alias" then
            eventParam = eventParam:ResolvePath(".")
        end
        if eventParam == nil then 
            log("Unresolved: ", eventParamPath) 
            return
        end
        eventParam = eventParam.AssignedParam or eventParam

        if eventParam:EntityType() ~= "Parameter" then
            log("Not a param")
            return
        end

        if self.RegisteredEventHandlers[eventParam] == nil then
            self.RegisteredEventHandlers[eventParam] = {}
        end
        self.RegisteredEventHandlers[eventParam][f] = true
    end


    function robotContext:WaitEvent(eventParamPath, timeout_or_event)
        local stubEntity = ag_utils.Entity:new({}, function() return "" end, function(s, id) return self:GlobalEntity(id) end)
        local eventParam = stubEntity:ResolvePath(eventParamPath)
        if eventParam == nil then
            log("Unresolved: ", eventParamPath)
        end
        eventParam = eventParam.AssignedParam or eventParam
        
        if eventParam.Type == "Alias" then
            eventParam = eventParam:ResolvePath(".")
        end
        if eventParam == nil then 
            log("Unresolved: ", eventParamPath) 
            return
        end
        eventParam = eventParam.AssignedParam or eventParam

        if eventParam:EntityType() ~= "Parameter" then
            log("Not a param")
            return
        end
        local event = scheduler.NewEvent()
        local ret
        local h = function(args)
            ret = args
            event:set()
        end
        if self.RegisteredEventHandlers[eventParam] == nil then
            self.RegisteredEventHandlers[eventParam] = {}
        end
        -- log("Added named event handler: ", self.ID, id)
        self.RegisteredEventHandlers[eventParam][h] = true
        local tt
        if type(timeout_or_event) == "number" then
            if timeout_or_event > 0 then
                tt = scheduler.addTask(function()
                    scheduler.sleep(timeout_or_event)
                    event:set()
                end)
            end
        else
            tt = scheduler.addTask(function()
                timeout_or_event:wait()
                event:set()
            end, "Waiter of cancelling event for '"..eventParamPath.."' actiongraph event")
        end
        event:wait()
        tt.cancel()
        self.RegisteredEventHandlers[eventParam][h] = nil

        return ret
    end

    function robotContext:getParamType(path) 
        local stubEntity = ag_utils.Entity:new({}, function() return "" end, function(s, id) return self:GlobalEntity(id) end)
        local root = stubEntity:ResolvePath(path)
        if root == nil then
            log("Unresolved: ", path) 
        end
        root = root.AssignedParam or root

        if root.Type == "Alias" then
            root = root:ResolvePath(".")
        end
        if root == nil then 
            log("Unresolved: ", root) 
            return
        end
        root = root.AssignedParam or root

        if root:EntityType() ~= "Parameter" then
            log("Not a param", path)
            return
        end

        return  root.Type, root.Mutable
    end
    function robotContext:SetParam(path, value)
        local stubEntity = ag_utils.Entity:new({}, function() return "" end, function(s, id) return self:GlobalEntity(id) end)
        local root = stubEntity:ResolvePath(path)
        if root == nil then 
            log("Unresolved: ", path) 
        end
        root = root.AssignedParam or root

        if root.Type == "Alias" then
            root = root:ResolvePath(".")
        end
        if root == nil then 
            log("Unresolved: ", root) 
            return
        end
        root = root.AssignedParam or root

        if root:EntityType() ~= "Parameter" then
            log("Not a param", path)
            return
        end
        if root.Mutable == false then
            log("Not mutable", path)
            return
        end
        return root:SetValue(value)
    end

    function robotContext:GetParam(path)
        local stubEntity = ag_utils.Entity:new({}, function() return "" end, function(s, id) return self:GlobalEntity(id) end)
        local root = stubEntity:ResolvePath(path)
        if root == nil then
            log("Unresolved: ", path) 
        end
        root = root.AssignedParam or root

        if root.Type == "Alias" then
            root = root:ResolvePath(".")
        end
        if root == nil then 
            log("Unresolved: ", root) 
            return
        end
        root = root.AssignedParam or root

        if root:EntityType() ~= "Parameter" then
            log("Not a param")
            return
        end

        if root.GetValue == nil then
            log("root:GetValue == nil", root)
            return
        end
        -- log(root)
        -- if root.Mutable == false then
        --     error("Not mutable")
        -- end
        
        return root:GetValue()
    end

    function robotContext:instantiateEntities()
        self:instantiateConfigs()
        self:instantiateHardware()
        self:instantiateGraphs()


        -- log(self:GlobalEntity("Graph"):ResolvePath(".ticker.ticked"))

        -- self:IterateEmbeddedEntitiesDependencyTreeBottomToTop("pidCoefs.P", function(e)
        --     log(e)
        -- end)
        -- self:IterateEmbeddedEntitiesDependencyTreeBottomToTop("Hardware", function(e)
        --     log(e)
        -- end)
        -- self:IterateEmbeddedEntitiesDependencyTreeBottomToTop("Graph", function(e)
        --     log(e)
        -- end)
        
        -- log(self:GlobalEntity("Hardware"):ResolvePath(".PID_P"))
        -- log(self:GlobalEntity("Hardware"):ResolvePath("Hardware.Actuator0.EstimatedPositionFeedbackSignal.scale"))
        -- log(self:GlobalEntity("Hardware"):ResolvePath(".Actuator0.PID_P"))

        -- log(self:GlobalEntity("Hardware"):ResolvePath(".board.stepperDriversModeSignal"))
        -- error("fu")
        -- local tmp = self:GlobalEntity("Hardware"):ResolvePath(".Actuator0.Motor.resolution")
                
                -- local tmp = self:GlobalEntity("Hardware"):ResolvePath("")
        -- log(tmp)

      
    end

    return robotContext
end
function NewModuleContext(path, base_dir, PACKAGE_PATHS)
    local abs_path = path_lib.abspath(path, base_dir)
    local dir_path = path_lib.dirname(abs_path)
   
    if not path_lib.exists(abs_path) or not path_lib.isfile(abs_path) then 
        error("module not found: "..abs_path)
    end
    local raw_structure = ag_utils.readSrc(abs_path)
    

    local moduleContext = {
        src_structure = raw_structure,
        dir_path = dir_path,
        path = path,
        packageSearchPaths = {path},
        GraphTypes = {},

        ImportedPackages = {},
        PACKAGE_PATHS = PACKAGE_PATHS
        

    }
  
    moduleContext.Robots = OrderedTable()
    local function dotPathToOsPath(dottedPath)
        local dotCount = 0
        for i = 1,dottedPath:len(),1 do
            if dottedPath:sub(i,i) == "." then
                dotCount = dotCount + 1
            else
                break
            end
        end
        local prefix = ""
        if dotCount == 0 then
            utils.errorExt("Unexpected")
        end
        if dotCount == 1 then 
            prefix = "."..path_lib.sep
        else
            for i = 1,dotCount-1,1 do
                prefix = ".."..path_lib.sep..prefix
            end
        end
        local ret = dottedPath:sub(dotCount + 1, -1)
        ret = ret:gsub("%.", path_lib.sep)
        ret = prefix..ret
        return ret
    end

    function moduleContext:resolveType(entityType, typeName)
        -- log("Resolving", entityType, typeName)

        local typeConstructor = require'interpreter.entity_constructors'.Resolve(entityType, typeName, self)

        if typeConstructor ~= nil then
            return typeConstructor
        end

        if self.src_structure.Import and self.src_structure.Import[entityType] then
            -- log("Searching in imports")
            for pkg_id, importing_objects in pairs(self.src_structure.Import[entityType]) do
                for _, importType in ipairs(importing_objects) do
                    if importType == typeName then
                        if self.ImportedPackages[pkg_id] == nil then
                            -- if pkg_id:match("^%.[a-zA-Z]+[0-9a-zA-Z]*")~= nil then
                            if pkg_id:sub(1,1) == "." then
                                pkg_id = dotPathToOsPath(pkg_id)

                                self.ImportedPackages[pkg_id] = NewModuleContext(pkg_id..require'interpreter.package_context'.SRC_EXENSION, dir_path, moduleContext.PACKAGE_PATHS)
                            else
                                self.ImportedPackages[pkg_id] = require'interpreter.package_context'.NewPackageContext(pkg_id, dir_path, moduleContext.PACKAGE_PATHS)
                            end
                        end
                        return self.ImportedPackages[pkg_id]:resolveType(entityType, typeName) 
                    end
                end
            end
        end
    end

    
    function moduleContext:instantiateRobots()
        if self.src_structure.Robots == nil then
            return
        end

        for robotID, robotSrc in pairs(self.src_structure.Robots) do
            local r = NewRobotContext(robotID, robotSrc, self)
            r:instantiateEntities()
            self.Robots[robotID] = r
        end
    end

    function moduleContext:iterateUserScripts(visitor)
        for robotId, robot in pairs(self.Robots) do
            robot:IterateUserScriptsBottomToTop(function(scriptPath, graph)
                visitor(scriptPath, graph, robotId)
            end)
        end
        if self.src_structure.Script ~= nil then
            local scrRelPath =  self.src_structure.Script
            if not path_lib.isabs(scrRelPath) then
                scrRelPath = path_lib.abspath(scrRelPath, self.dir_path)
            end
            visitor(scrRelPath, nil, nil)
        end
    end

    function moduleContext:EntityBySourceCodeCoordinates(row, column)
    end

    

    return moduleContext
end


return P
