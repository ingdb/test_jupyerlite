
local ag_utils = require'interpreter.helpers'
local OrderedTable = require"orderedtable"
local log
function NewConfiguration(src, parentEntity, id, moduleContext, robotContext)
    -- log("NewConfiguration", id)
    local c = {
        id = id,
        parentEntity = parentEntity,
        ModuleContext = moduleContext,
        Parameters = OrderedTable(),
        BatchMapping = nil,
        RobotContext = robotContext
    }
    c.Configuration = c
    if src ~= nil then 
        for paramName, paramSrc in pairs(src) do
            if paramName ~= '*' then
                local param = CreateParam(paramSrc, c, paramName, moduleContext, robotContext)
                c.Parameters[paramName] = param
            end
        end
        if src['*'] ~= nil then
            local batchTargets = src['*']
            if type(batchTargets) == "string" then
                c.BatchMapping = {batchTargets}
            elseif type(batchTargets) == "table" then
                if src['*'][1] == nil then
                    error("unsupported batch mapping")
                end
                c.BatchMapping = {}
                for _, mapTrg in ipairs(batchTargets) do
                    table.insert( c.BatchMapping, mapTrg )
                end
            else
                error("unsupported batch mapping")
            end
        end
    end

    function c:assignParams(sourceConfig)

        -- log(self:Parent())
        if sourceConfig.BatchMapping then 
            
            for _, batchMappingTarget in ipairs(sourceConfig.BatchMapping) do
                local isParentRelation = true
                if string.len( batchMappingTarget ) % 2 ~= 0 then
                    isParentRelation = false
                else
                    for c in batchMappingTarget:gmatch"." do
                        if c ~= '.' then
                            isParentRelation = false
                            break
                        end
                    end
                end
                if isParentRelation == true then            
                    for paramName, param in pairs(self.Parameters) do
                        param:Assign(CreateParam(batchMappingTarget..paramName, c, paramName, c.ModuleContext, c.RobotContext))
                    end
                end
            end
            -- log("doing batch mapping to configs for ", c.parentEntity.id)
            for _, batchMappingTarget in ipairs(sourceConfig.BatchMapping) do
                if batchMappingTarget ~= ".." then
                    if batchMappingTarget.sub(1, 1) ~= "." then
                        local confToTest = self.RobotContext.Entities.Configurations[batchMappingTarget]
                        if confToTest ~= nil then
                            for paramName, param in pairs(self.Parameters) do
                                if confToTest.Parameters[paramName] ~= nil then
                                    log("found for ", paramName)
                                    -- TODO
                                    param.Assign(CreateParam(batchMappingTarget..'.'..paramName, nil, nil, c.ModuleContext, c.RobotContext))
                                end
                            end
                        end
                    else
                        error("unimplemented param automap target")
                    end
                end
            end
        end

        -- log(self:Parent())
        for assignParamName, assignParam in pairs(sourceConfig.Parameters) do
            -- log(assignParamName)
            
            if self.Parameters[assignParamName] ~= nil then
                self.Parameters[assignParamName]:Assign(assignParam)
            end
        end
    end
 
    function c:ToString()
        local s = ""
        for id, p in pairs(self.Parameters) do 
            s = s .. id .. " " 
        end
        return string.format( "Parameters: %s" , s)
    end
    function c:ID()
        return self.id
    end

    function c:Children()
        local r = OrderedTable()
        for k, v in pairs(self.Parameters) do 
            r[k] = v
        end
        return r
    end
    function c:Parent()
        return self.parentEntity
    end

    function c:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
        local alreadyVisited = alreadyVisited or {}

        for _, v in pairs(self.Parameters) do 
            -- ag_utils.log("HERE")
            if v.Mutable then
                v:IterateEmbeddedEntitiesDependencyTreeBottomToTop(visitor, alreadyVisited)
            end
        end       
    end

    return ag_utils.Entity:new(c, function() return "Configuration" end, function(s, id) return s.RobotContext:GlobalEntity(id) end)
end

function resolveConfType(typeRawData, newTypeName, typeModuleContext)
    return function(module_context, name, robotContext) 
        -- log("Instantiating ", newTypeName)
        return NewConfiguration(typeRawData, nil, name, module_context, robotContext)
    end
end
