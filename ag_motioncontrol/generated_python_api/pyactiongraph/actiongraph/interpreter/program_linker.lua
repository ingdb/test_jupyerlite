
local P = {}   -- package

local OrderedTable = require'orderedtable'
local log = require"interpreter.helpers".log
local errorExt = require"utils".errorExt
local MakeClass = require'classes'.MakeClass
local embeddedNodeTypes = require'interpreter.embedded_node_types'
local embeddedHardwareTypes = require'interpreter.embedded_hw_types'
local path_lib = require'pl.path'
local json = require'json'

local entitiesMetas = OrderedTable()

entitiesMetas.Graph = {
    entityExternTypeClass = "ExternGraphTypeName",
    entityExportedTypeClass = "ExportedGraphTypeName",
    entityTypeIDClass = "GraphTypeID",
    entityInstanceClass = "GraphInstance",
    entityTypeDeclarationClass = "GraphTypeDeclaration",
    entityDerivedTypeDeclarationClass = "GraphDerivedTypeDeclaration",
    entityNewTypeDeclarationClass = "GraphNewTypeDeclaration",
    embeddedTypes = embeddedNodeTypes,
    entityTypeId = "ModuleDefinedGraphTypeID",
    childInstanceId = "ChildGraphNodeInstanceID"
}
entitiesMetas.Hardware = {
    entityExportedTypeClass = "ExportedHardwareTypeName",
    entityExternTypeClass = "ExternHardwareTypeName",
    entityTypeIDClass = "HardwareTypeID",
    entityInstanceClass = "HardwareModuleInstance",
    entityTypeDeclarationClass = "HardwareTypeDeclaration",
    entityDerivedTypeDeclarationClass = "HardwareDerivedTypeDeclaration",
    entityNewTypeDeclarationClass = "HardwareNewTypeDeclaration",
    embeddedTypes = embeddedHardwareTypes,
    entityTypeId = "ModuleDefinedHardwareTypeID",
    childInstanceId = "ChildHardwareModuleInstanceID"
}
entitiesMetas.Configuration = {
    entityExportedTypeClass = "ExportedConfigurationTypeName",
    entityExternTypeClass = "ExternConfigurationTypeName",
    entityTypeIDClass = "ConfigurationTypeID",
    entityInstanceClass = "ConfigurationInstance",
    entityTypeDeclarationClass = "ConfigurationTypeDeclaration",
    entityDerivedTypeDeclarationClass = "ConfigurationDerivedTypeDeclaration",
    entityNewTypeDeclarationClass = "ConfigurationDeclaration",
    embeddedTypes = nil,
    entityTypeId = "ModuleDefinedConfigurationTypeID",
}

local ConfigurationDeclarationClass = "ConfigurationDeclaration"
local ConfigurationAssignmentClass = "ConfigurationAssignment"
local ParameterAliasClass = "ParameterAlias"
local ParameterPureAliasClass = "PureAliasParameter"
local ParameterInstanceClass = "ParameterInstance"
local ParameterDeclarationClass = "ParameterDeclaration"
local AssignTargetParameterIDClass = "AssignTargetParameterID"
local BatchParameterAssignTargetClass = "BatchParameterAssignTarget"
local DeclaredParameterIDClass = "DeclaredParameterID"
local SRC_NULL = require "lyaml".null
local RobotConfigClass = "RobotConfig"
local RobotIDClass = "RobotID"
local FixedKeywordClass = "FixedKeyword"
local UnresolvedType = MakeClass({block = nil, kind = "", module = {}}, setmetatable({}, {__tostring = function(self)return "Unresolved "..self.kind.." type'"..self.block.Content.."'" end}))
local EmbeddedType = MakeClass({block = nil, EmbeddedTypeSrc = nil, kind = ""}, setmetatable({}, {__tostring = function(self)return "Embedded "..self.kind.." '"..self.block.Content.."'" end}))
local NewType = MakeClass({block = nil, kind = "", module = {}}, setmetatable({}, {__tostring = function(self)return "New "..self.kind.." Type: "..self.block:__tostring() end}))
local DerivedEntityType = MakeClass({block = nil, kind = "", module = {}}, setmetatable({}, {__tostring = function(self)return "Derived "..self.kind.." Type: "..self.block:__tostring() end}))

local ImportedType = MakeClass({block = nil, pkgID = "", kind = "", module = nil}, setmetatable({}, {__tostring = function(self)return "Imported "..self.kind.." Type: "..self.pkgID.." "..self.block:__tostring() end}))
local ExportedType = MakeClass({block = nil, pkgID = "", kind = "", module = nil}, setmetatable({}, {__tostring = function(self)return "Exported "..self.kind.." Type: "..self.pkgID.." "..self.block:__tostring() end}))

local ParameterTypeDecl = MakeClass({block = nil }, setmetatable({}, {__tostring = function(self)return "Param type declaration ".." '"..self.block:__tostring().."'" end}))
local ParameterEmbeddedTypeDecl = MakeClass({content = nil }, setmetatable({}, {__tostring = function(self)return "Param embedded declaration"end}))
P.paramUnresolved = {}


local ParameterAlias


P.resolver = function(self, rootGetter)
    if self.resolvedTo ~= false then
        return self.resolvedTo
    end
    local root = {
        getChild = function(self, name) return rootGetter(name)end
    }
    local currentInstance = self.parent
    for _,step in ipairs(self.targetPath) do
        if getmetatable(step) == P.aliasPathGoToChild then
            if currentInstance == P.paramUnresolved then
                self.resolvedTo = P.paramUnresolved
                return self.resolvedTo
            end
            currentInstance = currentInstance:getChild(step.childName)
            if currentInstance == nil then
                self.resolvedTo = P.paramUnresolved
                return self.resolvedTo
            end
            if currentInstance:isInstance(ParameterAlias) then
                currentInstance = currentInstance:resolve(rootGetter)
            end
            
        elseif step == P.aliasPathStepSwitchToParent then
            if currentInstance == root then
                self.resolvedTo = P.paramUnresolved
                return self.resolvedTo
            end
            if currentInstance.parentInstance == nil then
                currentInstance = root
            else
                currentInstance = currentInstance.parentInstance
            end
            if currentInstance == nil then
                self.resolvedTo = P.paramUnresolved
                return self.resolvedTo
            end
        elseif step == P.aliasPathStepSwitchToRoot then
            currentInstance = root
        elseif step == P.aliasPathStepUndefined then
            -- log("alias ", self, " is unassigned")
            self.resolvedTo = P.paramUnresolved
            return self.resolvedTo
        else
            errorExt("Internal error")
        end
    end
    if currentInstance ~= P.paramUnresolved then
        table.insert(currentInstance.referencedBy, self)
        if currentInstance:isInstance(ParameterAlias) then
            currentInstance = currentInstance:resolve(rootGetter)
        end
    end 
   
    self.resolvedTo = currentInstance
    return self.resolvedTo
end
ParameterAlias = MakeClass(   {block = nil, targetPath = {}, referencedBy = {} }, 
                                    setmetatable({
                                        resolvedTo=false,
                                        resolve = P.resolver,
                                        BuildPath = function(self, withTypeInfo)
                                            return self.parent:BuildPath(withTypeInfo).."."..self.name
                                        end
                                    }, {
                                        __tostring = function(self)
                                            return "Param alias to "..P.stringifyPath(self.targetPath).." '"..self.block:__tostring().."'" 
                                        end
                                    })
                                )
local ParameterValue = MakeClass({block = nil, referencedBy = {} }, setmetatable({
    resolve = function(self)return self end,
    BuildPath = function(self, withTypeInfo)
        return self.parent:BuildPath(withTypeInfo).."."..self.name
    end
    }, {
    __tostring = function(self)return "Parameter value '"..self.block:__tostring().."'" end,
    
    }))

local Instance = MakeClass({
    block = {}, type = {}, baseType = {}, kind = "", configurationsStack = OrderedTable(), children = OrderedTable(),
    resolvedParams = OrderedTable(),
    iterateTypeChain = function(slf, visitor) P.iterateInstanceTypeChain(slf.type, visitor) end,
    finalizeType = function(...) P.finilizeInstanceType(...) end
}, setmetatable({
    getChild = function(self, name) 
        for k, v in pairs(self.children) do
            if k.Content == name then return v end
        end

        for k, v in pairs(self.parameters) do
            if k == name then return v.chain[1] end
        end
    end,
    BuildPath = function(self, withTypeInfo)
        local nameString = self.name
        
        if withTypeInfo and self.finalTypeName ~= "" then
            if self.finalTypeName ~= nil and self.finalTypeName ~= "" then
                nameString = string.format("%s(%s)", nameString, self.finalTypeName)
            end
            
        end
        if self.parentInstance then
            return self.parentInstance:BuildPath(withTypeInfo).."."..nameString
        else
            return nameString
        end
    end
}, {__tostring = function(self)return "Instance "..self.kind.." "..self.block:__tostring() end}))



P.aliasPathStepSwitchToParent = setmetatable({}, {__tostring=function()return " ↑" end})
P.aliasPathStepSwitchToRoot = setmetatable({}, {__tostring=function()return " →√" end})
P.aliasPathStepUndefined = setmetatable({}, {__tostring=function()return " ??" end})
P.aliasPathGoToChild =   {__tostring=function(self)return " →"..self.childName end}
P.createAliasPathGoToChild = function(childName) return setmetatable({childName = childName}, P.aliasPathGoToChild) end
function P.normalizeInstancePath(...)
    local path_components = {...}
    local resolvedPathSteps = setmetatable({}, {__tostring = P.stringifyPath})
   
    if #path_components == 0 or #path_components == 1 and (path_components[1] ==SRC_NULL or path_components[1] == nil)then
        table.insert(resolvedPathSteps, P.aliasPathStepUndefined)
        return resolvedPathSteps
    end

    for _, path in ipairs(path_components) do
        if path == nil or path == SRC_NULL then
            table.insert(resolvedPathSteps, P.aliasPathStepUndefined)
        else
            local index = 1
            if path:sub(1,1)~= "." then
                index = 1
                table.insert(resolvedPathSteps, P.aliasPathStepSwitchToRoot)
            end
            while index <= #path do
                if index == path:find("..", index, true) then
                    index = index + 2
                    table.insert(resolvedPathSteps, P.aliasPathStepSwitchToParent)
                elseif index == path:find(".", index, true) and path:sub(index + 1, index + 1) ~= "." then
                    index = index + 1
                else
                    local endindex = path:find(".", index, true)
                    if endindex == nil then
                        table.insert(resolvedPathSteps, P.createAliasPathGoToChild(path:sub(index)))
                        index = #path + 1
                    else
                        table.insert(resolvedPathSteps, P.createAliasPathGoToChild(path:sub(index, endindex - 1)))
                        index = endindex
                    end
                end
            end
        end
    end
    return resolvedPathSteps
end
function P.stringifyPath(normalizedPath)
    if #normalizedPath == 0 then return "<undefined alias>" end
    local r = ""
    for _, p in ipairs(normalizedPath) do
        r = r .. tostring(p)
    end
    return r
end

function P.finilizeInstanceType(instance) -- TODO refactor this all to use yaml-defined embedded type

    local block = instance.block
    local tp = instance.module:resolveType(instance.block, instance.kind)

    
    
    instance.type = tp
    local configurationStack = {}
    local ok = true
    if tp == nil then
        errorExt("Internal Error: Unknown type for instance", block)
        return
    end
    local finalTypeName
    while tp ~= nil do
        if finalTypeName == nil then
            if tp.block:isOneOfClasses({entitiesMetas[instance.kind].entityTypeIDClass, entitiesMetas[instance.kind].entityExternTypeClass}) then
                finalTypeName = tp.block.Content
            else
                local derivedBaseNameBlock = tp.block:getChildValueByClass(entitiesMetas[instance.kind].entityTypeIDClass)
                if derivedBaseNameBlock then
                    finalTypeName = derivedBaseNameBlock.Content
                end
            end
            
        end
        local conf = tp.block:getChildValueByClass(ConfigurationDeclarationClass) or tp.block:getChildValueByClass(ConfigurationAssignmentClass)
        if not conf then -- TODO need to be refactored somehow, looks line a hack specifically fo Configuration class
            if tp.block:isOneOfClasses(ConfigurationDeclarationClass) then conf = tp.block end
        end
        if conf then
            table.insert(configurationStack, 1, conf)
        end
        if tp.baseType == nil then
            break
        end
        tp = tp.baseType
    end
    instance.baseType = tp
    instance.finalTypeName = finalTypeName
    local parameters = OrderedTable()
    instance.parameters = parameters
    local startIndex
    if instance.baseType:isInstance(EmbeddedType) then
        startIndex = 1
        for paramName, paramDecl in pairs(instance.baseType.EmbeddedTypeSrc.Parameters) do
            local fakeBlock = {__tostring = function()return "N/A" end}

            parameters[paramName] = {
                embedded = true,
                type = ParameterEmbeddedTypeDecl{content = paramDecl}, -- TODO, need to use parsed embedded entities directly
                chain = {ParameterAlias{parent = instance, targetPath= P.normalizeInstancePath(), referencedBy = {},resolvedTo=false, block=fakeBlock, name=paramName}},
                valid = true
            }
        end
    else
        local confDeclaration = instance.baseType.block:getChildValueByClass(ConfigurationDeclarationClass)
        if not confDeclaration then
            if instance.baseType.block:isOneOfClasses(ConfigurationDeclarationClass) then confDeclaration = instance.baseType.block end
        end
        startIndex = 2
        if confDeclaration then
            confDeclaration:visitChildrenByClass({DeclaredParameterIDClass, ParameterDeclarationClass}, function(childKeyBlock, childInstanceBlock)
                if childInstanceBlock:isOneOfClasses({ParameterInstanceClass}) then
                    parameters[childKeyBlock.Content] = {
                        embedded = false,
                        type = ParameterTypeDecl{block = childInstanceBlock},
                        chain = {ParameterValue{parent = instance,block=childInstanceBlock, referencedBy = {}, name = childKeyBlock.Content}},
                        valid = true
                    }
                else
                    parameters[childKeyBlock.Content] = {
                        embedded = false,
                        type = nil,
                        chain = {ParameterAlias{parent = instance, targetPath= P.normalizeInstancePath(childInstanceBlock.Content), block = childInstanceBlock, referencedBy = {},resolvedTo=false, name = childKeyBlock.Content}},
                        valid = true
                    }
                end
                
            end)
        end
    end
    for i = startIndex,#configurationStack do
        configurationStack[i]:visitChildrenByClass({BatchParameterAssignTargetClass, ParameterAliasClass}, function(childKeyBlock, childInstanceBlock)
            if not childKeyBlock or not childInstanceBlock then return end
            for key, prm in pairs(parameters) do
                table.insert(prm.chain, 1, ParameterAlias{block = childInstanceBlock, parent = instance, targetPath= P.normalizeInstancePath(childInstanceBlock.Content,'.'..key), referencedBy = {},resolvedTo=false,name = key }) -- TODO handling batch assignment syntax sugar
            end
        end)
      
        configurationStack[i]:visitChildrenByClass({AssignTargetParameterIDClass, ParameterAliasClass, ParameterPureAliasClass}, function(childKeyBlock, childInstanceBlock)
            if not childKeyBlock or not childInstanceBlock then return end
            if not parameters[childKeyBlock.Content] then
                parameters[childKeyBlock.Content] = {
                    embedded = false,
                    type = nil,
                    chain = {ParameterAlias{parent = instance, targetPath= P.normalizeInstancePath(childInstanceBlock.Content), block = childInstanceBlock, referencedBy = {},resolvedTo=false, name = childKeyBlock.Content}},
                    valid = true
                }
            else
                table.insert(parameters[childKeyBlock.Content].chain, 1, ParameterAlias{parent = instance, targetPath= P.normalizeInstancePath(childInstanceBlock.Content), block = childInstanceBlock, referencedBy = {},resolvedTo=false, name = childKeyBlock.Content})
            end
        end)
        configurationStack[i]:visitChildrenByClass({AssignTargetParameterIDClass, ParameterInstanceClass}, function(childKeyBlock, childInstanceBlock)
            if not childKeyBlock or not childInstanceBlock then return end
          
            if not parameters[childKeyBlock.Content] then
                parameters[childKeyBlock.Content] = {
                    embedded = false,
                    type = ParameterTypeDecl{block = childInstanceBlock},
                    chain = {ParameterValue{parent = instance, block=childInstanceBlock, referencedBy = {}, name = childKeyBlock.Content}},
                    valid = true
                }
            elseif not parameters[childKeyBlock.Content].type then
                table.insert(parameters[childKeyBlock.Content].chain, 1, ParameterValue{parent = instance, block=childInstanceBlock, referencedBy = {}, name = childKeyBlock.Content}) -- untyped
            else
                -- log("Embedded entities parameter type checking is not implemented")
                -- TODO add type checks here
                local typeToCheck = parameters[childKeyBlock.Content].type
                table.insert(parameters[childKeyBlock.Content].chain, 1, ParameterValue{parent = instance, block=childInstanceBlock, referencedBy = {}, name = childKeyBlock.Content})      
            end
            
        end)
    end
    
end

function P.iterateInstanceTypeChain(type, visitor)
    if type.baseType ~= nil then
        P.iterateInstanceTypeChain(type.baseType, visitor)
    end
    visitor(type)
end


function P.ProgramLinker(modulesProvider, packagePaths)
    local ret = {
        modules = OrderedTable(),
        modulesProvider = modulesProvider,
        packagePaths = function()
            local paths = packagePaths() or {}
            if type(paths) == 'string' then 
                local t={}
                for str in string.gmatch(paths, "([^;]+)") do
                        table.insert(t, str)
                end
                paths = t
            end
            return paths
        end
    }
    setmetatable(ret, {__index = P})
    return ret
end

local Module = {}
function P:NewModule(path)
    local ret = {
        linker = self,
        path = path_lib.abspath(path),
        resolvedTypes = OrderedTable(),
        exportedTypes = OrderedTable(),
        importedTypes = OrderedTable(),
        dependencies = {},
        robotInstances = OrderedTable()
    }
    for entityKind, meta in pairs(entitiesMetas) do
        ret.resolvedTypes[entityKind] = OrderedTable()
        ret.exportedTypes[entityKind] = OrderedTable()
        ret.importedTypes[entityKind] = OrderedTable()
    end

    setmetatable(ret, {__index = Module})


    local parsedModule = self.modulesProvider(path)
    if parsedModule == nil then 
        log("No parsed module with path", path)
        return
    end
    local rootCodeBlock = parsedModule.rootCodeBlock
    ret.rootCodeBlock = parsedModule.rootCodeBlock
    if not rootCodeBlock or rootCodeBlock.Classes[1].Valid ~= true then
        log(path, "module is broken")
    end

    return ret
end

function Module:DependsOnPath(path)
    if path == self.path then return true end
    for  m, _ in pairs(self.dependencies) do
        if m:DependsOnPath(path) then return true end
    end
    return false
end

function Module:IsBroken()
    return not self.rootCodeBlock or self.rootCodeBlock.Classes[1].Valid ~= true
end
local RootConfigurationClass = MakeClass({}, setmetatable({}, {__tostring = function(self)return "Root configurations"end})) -- TODO looks like a hack

function Module:resolveEntityParameters()
    
    for k, robot in pairs(self.robotInstances) do
       

        if robot.Valid then
            local rootCOnfigurations = RootConfigurationClass({
                parameters = {},
                children = {},
                getChild = function(self, name) 
                    for k, v in pairs(robot.Instances.Configuration) do
                        if k.Content == name then
                            return v
                        end
                    end
                end
            })
            local rootGetter = function(name)
                if name == "Configuration" then
                    return rootCOnfigurations
                elseif robot.Instances[name] then
                    for _, v in pairs(robot.Instances[name]) do
                        return v
                    end
                end    
            end
            for entityKind, entityMap in pairs(robot.Instances) do
                for rootInstanceKey, rootInstance in pairs(entityMap) do
                    -- print("Root instance: ", rootInstanceKey, rootInstance)
                    self:visitInstanceRecursively(rootInstance, function(instance)
                        for paramName, paramData in pairs(instance.parameters) do
                            if paramData.chain[1]:isInstance(ParameterAlias) then

                                local resolved = paramData.chain[1]:resolve(rootGetter)
                                if resolved == P.paramUnresolved then
                                    if not instance.baseType:isInstance(EmbeddedType) then
                                        print("instance: ", instance)
                                        print("\t\tUNRESOLVED PARAM", paramData.chain[1])
                                    else
                                        local isOptional = false
                                        if instance.baseType.EmbeddedTypeSrc.OptionalParams then --TODO switch to parsing of embedded types the same way it is done for user types
                                            for _, optionalName in ipairs( instance.baseType.EmbeddedTypeSrc.OptionalParams) do
                                                if optionalName == paramName then
                                                    isOptional = true
                                                    break
                                                end
                                            end
                                        end
                                        if not isOptional then
                                            print("instance: ", instance)
                                            print("\t\tUNRESOLVED PARAM", paramData.chain[1])
                                        end

                                    end
                                else
                                    -- print("\t\t",  paramData.chain[1], "\n                               -> \n                                    ", resolved)
                                end
                            elseif paramData.chain[1]:isInstance(ParameterValue) and paramData.chain[1].block:isOneOfClasses({"ParameterInstanceExpression"}) then
                                log("resolving expressions is not supported yet")
                            end
                            
                        end
                    end)
                end
            end
        end
    end
end

function Module:Build()
    self:createTopLevelInstances()

    self:resolveEntityParameters()
    
end

Module.entitiesMetas = entitiesMetas

function Module:resolveExportedType(name, entityKind)
    local meta = entitiesMetas[entityKind]
    if self.exportedTypes[entityKind][name] == nil then

        local ComponentsSection = self.rootCodeBlock:getChildValueByClass('TypesDeclaration')
        if ComponentsSection then
            local baseType
            local tp
            ComponentsSection:visitChildrenByClass({meta.entityTypeDeclarationClass, meta.entityTypeId}, function(keyBlock, valueBlock) 
                
                if valueBlock and keyBlock and keyBlock.Content == name then
                    baseType = self:resolveType(valueBlock, entityKind)
                    tp = ExportedType{block = valueBlock, kind = entityKind, baseType = baseType, module=self}
                    return false
                end
            end, 1) 
            if tp then
                self.exportedTypes[entityKind][name] = tp
            end

        else
            local pkgId
            local resolvedEnt
            self.rootCodeBlock:visitChildrenByClass({"ExportSourcePackageName", entitiesMetas[entityKind].entityExportedTypeClass}, function(keyBlockPkgId, exportedTypeNameBlock)
                if keyBlockPkgId then
                    pkgId = keyBlockPkgId.Content
                end
                if exportedTypeNameBlock then
                    if name == exportedTypeNameBlock.Content then
                        local peerModule = self:loadPeerModule(pkgId, true)
                        local exp = peerModule:resolveExportedType(name, entityKind)
                        resolvedEnt = ExportedType{block = exportedTypeNameBlock, kind = entityKind, baseType = exp, module = self}
                        self.exportedTypes[entityKind][name] = resolvedEnt
                        return false
                    end
                end
            end)

        end

    end

    return self.exportedTypes[entityKind][name]
end

function Module:tryImportType(name, entityKind)
    local resolvedEnt
    local pkgId

    if self.importedTypes[entityKind][name] ~= nil then
        return self.importedTypes[entityKind][name]
    end
    self.rootCodeBlock:visitChildrenByClass({"ImportSourcePackageName", entitiesMetas[entityKind].entityExternTypeClass}, function(keyBlockPkgId, importedTypeNameBlock)
        if keyBlockPkgId then
            pkgId = keyBlockPkgId.Content
        end
        if importedTypeNameBlock then
            if name == importedTypeNameBlock.Content then
                local peerModule = self:loadPeerModule(pkgId)
                local exp = peerModule:resolveExportedType(name, entityKind)
                resolvedEnt = ImportedType{block = importedTypeNameBlock, kind = entityKind, baseType = exp, module = self}
                self:addResolvedType(entityKind, importedTypeNameBlock, resolvedEnt)
                self.importedTypes[entityKind][name] = resolvedEnt
                return false
            end
        end
    end)

    return resolvedEnt
end

function Module:resolveType(block, entityKind)
    local meta = entitiesMetas[entityKind]
    if self.resolvedTypes[entityKind][block] ~= nil then
        return self.resolvedTypes[entityKind][block]
    end
    if block:isOneOfClasses(meta.entityTypeIDClass) then
        local IdToResolve = block.Content

        if meta.embeddedTypes and meta.embeddedTypes[IdToResolve] ~= nil then
            local emb = EmbeddedType{block = block, EmbeddedTypeSrc = meta.embeddedTypes[IdToResolve](), kind = entityKind}
            self:addResolvedType(entityKind, block,  emb)
            return emb
        else
            local prn = block.ParentBlock
            while prn ~= nil do
                local ComponentsSection = prn:getChildValueByClass('TypesDeclaration')
                if ComponentsSection then
                    local baseType
                    ComponentsSection:visitChildrenByClass({meta.entityTypeDeclarationClass, meta.entityTypeId}, function(keyBlock, valueBlock) 
                        
                        if valueBlock and keyBlock and keyBlock.Content == IdToResolve then
                            baseType = self:resolveType(valueBlock, entityKind)
                            return false
                        end
                    end, 1) 
                    if baseType then
                        local tp = DerivedEntityType{block = block, kind = entityKind, baseType = baseType, module = self}
                        self:addResolvedType(entityKind, block, tp)
                        return tp
                    end
                end
                prn = prn.ParentBlock
            end

            local imported = self:tryImportType(IdToResolve, entityKind)
            if imported then
                self:addResolvedType(entityKind, block, imported)
                return imported
            end

            local tp = UnresolvedType{block = block, kind = entityKind, module = self}
            self:addResolvedType(entityKind, block, tp)
            return tp
        end
    elseif block:isOneOfClasses(meta.entityNewTypeDeclarationClass) then
        local tp = NewType{block = block, kind = entityKind, module = self}
        self:addResolvedType(entityKind, block,  tp)
        return tp
    elseif block:isOneOfClasses(meta.entityDerivedTypeDeclarationClass) then
        local derivedFrom = block:getChildValueByClass(meta.entityTypeDeclarationClass)
        if derivedFrom == nil then errorExt("here") end
        local tp = DerivedEntityType{block = block, kind = entityKind, baseType = self:resolveType(derivedFrom, entityKind), module = self}
        self:addResolvedType(entityKind, block,  tp)
        return tp
    else
        errorExt("here")
    end
end

function Module:addResolvedType(entityKind, block, typeEntity)
    self.resolvedTypes[entityKind][block] = typeEntity
end



function Module:recursiveResolveInstance(instanceBlock, entityKind, parentInstance, parentScopeName)
    local newInstance = Instance({module = self, kind = entityKind, block = instanceBlock, children = OrderedTable(), parameters = OrderedTable(), parentInstance = parentInstance, referencedBy = {}, name = parentScopeName, finalTypeName = ""})
    newInstance:finalizeType()

    if newInstance.baseType:isInstance(UnresolvedType) then
        log("Unresolved type for ", instanceBlock)
        return nil
    end
    local instanceModule = newInstance.baseType.module

    
    local childrenOk = true
    newInstance.baseType.block:visitChildrenByClass({entitiesMetas[entityKind].entityInstanceClass, entitiesMetas[entityKind].childInstanceId, "ListIndex"}, function(childKeyBlock, childInstanceBlock)
        if not childKeyBlock or not childInstanceBlock then return end
        local resolvedChild = instanceModule:recursiveResolveInstance(childInstanceBlock, entityKind, newInstance, childKeyBlock.Content)
        if resolvedChild then
            newInstance.children[childKeyBlock] = resolvedChild
        else
            childrenOk = false
        end
    end)

    if childrenOk == false then return nil end
    return newInstance
end

function Module:createTopLevelInstances()
    self.rootCodeBlock:visitChildrenByClass({RobotConfigClass, RobotIDClass}, function(robotIdBlock, robotConfigBlock)
        if not robotIdBlock or not robotConfigBlock then return end
        local newRobot = {
            Valid = true,
            Instances = OrderedTable()
        }
      
        self.robotInstances[robotIdBlock] = newRobot
        for entityKind, meta in pairs(entitiesMetas) do
            newRobot.Instances[entityKind] = OrderedTable()
        end
       
        for entityKind, meta in pairs(entitiesMetas) do
            robotConfigBlock:visitChildrenByClass({meta.entityInstanceClass, FixedKeywordClass, meta.entityTypeId}, function(keyBlock, instanceBlock)
                if keyBlock == nil or instanceBlock == nil then return end
                local inst = self:recursiveResolveInstance(instanceBlock, entityKind, nil, entityKind)
                if not inst then
                    newRobot.Valid = false
                else
                    newRobot.Instances[entityKind][keyBlock] = inst
                end
            end, 1)
        end

    end, 1)
  
end

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
        errorExt("Unexpected")
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



function Module:loadPeerModule(pkgID, compatMode)
    local thisDirPath = path_lib.dirname(path_lib.abspath(self.path))

    if compatMode then
        log("EXPORT SECTION COMPAT MODE!! Need to change file names in Export section to dot-format")
        pkgID = "."..pkgID
    end

    if pkgID:sub(1, 1) ~= "." then
        for _, pkgPath in ipairs(self.linker.packagePaths()) do
            local pkgPath = path_lib.abspath(pkgPath)
            local manifestPath = path_lib.join(pkgPath, pkgID, "__index__.yaml")
            if path_lib.exists(manifestPath) then
                local m = self.linker:createModule(manifestPath)
                if m:IsBroken() == false then
                    self.dependencies[m] = true
                    return m
                end
            end
        end
        log("Failed to import package", pkgID)
    else
        local osPath = dotPathToOsPath(pkgID)
        local peerModulePath = path_lib.join(thisDirPath, osPath..'.yaml')
        local m = self.linker:createModule(peerModulePath)
        if m:IsBroken() == false then
            self.dependencies[m] = true
            return m
        end
        
    end
end



function Module:EntitiesByTextCoordinates(query)
    errorExt("deprecated")
    -- if self:IsBroken() then return nil, false end
    -- local result = {}
    -- local blocksToTest = self.rootCodeBlock:CollectChildrenByTextCoord(query, result)
    -- for _, block in ipairs(blocksToTest) do
    --     if self.blocksToEntitiesMap[block] then return self.blocksToEntitiesMap[block], true end
    -- end
    -- return nil, true
end


function P:createModule(entryPointModulePath)
    entryPointModulePath = path_lib.abspath(entryPointModulePath)
    if self.modules[entryPointModulePath] ~= nil then
        return  self.modules[entryPointModulePath]
    end
    local module =  self:NewModule(entryPointModulePath)
    self.modules[entryPointModulePath] = module
    return module
end
function P:AddModule(entryPointModulePath)
    entryPointModulePath = path_lib.abspath(entryPointModulePath)
    local module =  self:createModule(entryPointModulePath)
    self.modules[entryPointModulePath] = module
    return module
end

function P:Build(modulePaths) -- TODO rebuild?
    if type(modulePaths) == "string" then modulePaths = {modulePaths} end
    if modulePaths == nil then
        for p, _ in pairs(self.modules) do table.insert(modulePaths, p) end
    end
    for _, p in ipairs(modulePaths) do
        if self.modules[p] == nil then
            errorExt("Cannot build Module which is not loaded: ", p)
        end
        self.modules[p]:Build()
    end
end

function P:RemoveModule(entryPointModulePath)
    entryPointModulePath = path_lib.abspath(entryPointModulePath)
    self.modules[entryPointModulePath] = nil
end

-- local recursionLevel = 0
function P:RebuildDependenciesForPath(path)    
    errorExt("deprecated")
    -- if recursionLevel > 100 then
    --     log("WARNING, looks like infinite recursion happened in RebuildDependenciesForPath ", path)
    --     return
    -- end
    -- recursionLevel = recursionLevel + 1
    -- local toRebuild = {}
    -- for pt, module in pairs(self.modules) do
    --     local isDep = module:DependsOnPath(path)
        
    --     if isDep then
    --         log("Module", pt, "depends on ", path, ":", isDep)
    --         toRebuild[pt] = module
    --     end
    -- end
    -- for k, v in pairs(toRebuild) do
    --     self.modules[k] = nil
    -- end
    -- for k, v in pairs(toRebuild) do
    --     log("Rebuilding linkage for path", k)
    --     self:AddModule(k)
    -- end
    -- recursionLevel = recursionLevel - 1
end

function P:EntitiesByTextCoordinates(path, query)
    errorExt("deprecated")
    -- path = path_lib.abspath(path)
    -- if self.modules[path] == nil then return nil end
    -- return self.modules[path]:EntitiesByTextCoordinates(query)
end

function Module:visitInstanceRecursively(inst, visitor)
    if inst.children == nil then
        log('FUUU')
    end
    for _, ch in pairs(inst.children) do
        self:visitInstanceRecursively(ch, visitor)
    end
    visitor(inst)
end
function Module:IterateInstances(visitor)
    for _, r in pairs(self.robotInstances)  do
        for entityType, instances in pairs(r.Instances) do
            for instKey, inst in pairs(instances) do
                self:visitInstanceRecursively(inst, visitor)
            end
        end
    end
end
function P:CollectSourceCodeFilesPaths()
    local srcs = {}
    local scripts = {}
    local scriptMap = {}
    for p, m in pairs(self.modules) do 
        table.insert(srcs, p) 
        m:IterateInstances(function (instance)
            if instance.kind ~= 'Graph' then return end
            local latestPath
            instance:iterateTypeChain(function(type) 
                local scriptBlock = type.block:getChildValueByClass("ScriptFilePath")
                if scriptBlock then
                    latestPath = path_lib.abspath(scriptBlock.Content, path_lib.dirname(type.block.SrcMeta.srcPath))
                end
            end)
            if latestPath then scriptMap[latestPath] = true end
        end)
    end
    for K, _ in pairs(scriptMap) do table.insert(scripts, K) end
    return srcs, scripts
end

function P:CollectInteractableEntities()
    local result = OrderedTable()

    for p, module in pairs(self.modules) do 
        for k, robot in pairs(module.robotInstances) do
            local robotRes = {
                mutableParameters = OrderedTable(),
                incomingEvents = OrderedTable(),
                outgoingEvents = OrderedTable()
            }
            result[k.Content] = robotRes
            if robot.Valid then
                for entityKind, entityMap in pairs(robot.Instances) do
                    for rootInstanceKey, rootInstance in pairs(entityMap) do
                        -- print("Root instance: ", rootInstanceKey, rootInstance)
                        module:visitInstanceRecursively(rootInstance, function(instance)
                            if instance.baseType == nil then
                                log("ffuu")
                            end
                            if instance.baseType:isInstance(EmbeddedType) then
                                local eventGroupName
                                if instance.baseType.EmbeddedTypeSrc.IsPCEventWaiter then
                                    eventGroupName = "incomingEvents"
                                elseif instance.baseType.EmbeddedTypeSrc.IsPCEventEmitter then
                                    eventGroupName = "outgoingEvents"
                                end
                                if eventGroupName then
                                    local resolvedEvent = instance.parameters.event.chain[1]:resolve() -- TODO this is a hack, we cannot know that event param is called "event"
                                    -- log(resolvedEvent)
                                    
                                    local internalPath
                                    local verbousPath
                                    local globalEventName
                                    if resolvedEvent == P.paramUnresolved then
                                        internalPath = instance:BuildPath()..".event"
                                        verbousPath = instance:BuildPath(true)
                                    else
                                        internalPath = resolvedEvent:BuildPath()
                                        verbousPath = resolvedEvent:BuildPath(true)
                                        if resolvedEvent:isInstance(ParameterValue) then
                                            
                                            local ok, _, eventName = resolvedEvent.block.Content:find("(%b<>)")
                                            if ok ~= nil then
                                                eventName = eventName:sub(2,-2)
                                                if eventName ~= nil and eventName ~= "" then
                                                    globalEventName = eventName
                                                end
                                            end
                                        end
                                    end
                                    robotRes[eventGroupName][internalPath] = {
                                        verbousPath = verbousPath,
                                        agAPIPath = internalPath,
                                        eventName = globalEventName or ""
                                    }
                                end
                            end
                            for paramName, paramData in pairs(instance.parameters) do
                                if paramData.chain[1]:isInstance(ParameterValue) then
                                    if paramData.chain[1].block:isOneOfClasses("ParameterInstanceMutable") and paramData.chain[1].block.Content.Internal ~= true then
                                        local internalPath = paramData.chain[1]:BuildPath()
                                        local verbousPath = paramData.chain[1]:BuildPath(true)
                                        robotRes.mutableParameters[internalPath] = {
                                            type = paramData.chain[1].block.Content.Type,
                                            verbousPath = verbousPath,
                                            agAPIPath = internalPath
                                        }
                                    end
                                end
                                
                            end
                        end)
                    end
                end
            end
        end
    end
    return result
end

return P
