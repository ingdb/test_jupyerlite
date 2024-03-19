local P = {} -- package

local OrderedTable = require "orderedtable"
local lyaml_lib = require "lyaml"
local log = require "interpreter.helpers".log
local errorExt = require "utils".errorExt
local SRC_NULL = lyaml_lib.null
P.SRC_NULL = SRC_NULL
local path_lib = require 'pl.path'
local languageSchema = require 'interpreter.yaml_schema'
local utils = require("utils")

local rex = require "rex_pcre"

local regex_flags = rex.flags().UTF8 + rex.flags().UCP
local function matchPattern(str, pattern)
    return rex.find(str, pattern, 1, regex_flags)
end

P.usecoloredoutput = true

local CodeBlock = {}

CodeBlock.__index = CodeBlock
function CodeBlock:print(indent)
    indent = indent or ""
    if self:hasNamedClasses() then
        print(indent, self:__tostring())
    end
    

    for _, class in ipairs(self.Classes) do
        class:print(indent.."  ")
    end
end

function CodeBlock:hasNamedClasses()
    for _, cl in ipairs(self.Classes) do
        if cl:hasNamedClasses() then
            return true
        end
    end
end

local color = require "color"

local function keywordsHighlight(str, clr, bold)
    if P.usecoloredoutput then
        if bold == true then
            return color.underline .. color.bold .. color.fg[clr] .. str .. color.reset
        else
            return color.fg[clr] .. str .. color.reset
        end
    end
    return str
end

function CodeBlock:__tostring()
    local srcPos = ""
    if self.SrcMeta then
        local filename = path_lib.basename(self.SrcMeta.srcPath)
        srcPos = string.format(" %s (%d,%d)-(%d,%d)", filename, self.SrcMeta.srcStart.line, self.SrcMeta.srcStart.column
            , self.SrcMeta.srcEnd.line, self.SrcMeta.srcEnd.column)
        srcPos = keywordsHighlight(srcPos, 'red')
    end
    local kind = ""

    for _, cl in ipairs(self.Classes) do
        if cl.Valid then
            if kind == "" then kind = cl:HierarchyAsString()
            else kind = kind ..";".. cl:HierarchyAsString() end
            
        end
    end
    if kind == "" then 
        kind = "<NO CLASSES>" 
    end
    -- if kind == "ActionGraphKeyword" then kind = keywordsHighlight(kind, 'yellow', true) end
    -- if self.Valid then kind = keywordsHighlight(kind, 'red') end

    local content = ""

    if self.Content == SRC_NULL then
        content = " ~ empty ~ "
    elseif type(self.Content) == 'table' then
        content = " ~ unknown structure ~ "
    elseif self.Content ~= nil then
        content = tostring(self.Content)
    end
    if content ~= "" then content = "(" .. keywordsHighlight(tostring(content), 'WHITE') .. ")" end

    return string.format("%s%s%s", kind, content, srcPos)
end

function CodeBlock:AddClass(class)
    class.Block = self
    table.insert(self.Classes, class)
end

local blockCacheByMeta = {}
function P.NewCodeBlock(content, meta, parentBlock)
    local o = {
        SrcMeta = meta,
        ParentBlock = parentBlock,
        Content = content,
        Classes = {},
    }

    setmetatable(o, CodeBlock)
    
    if meta then
        if blockCacheByMeta[meta] == nil then
            blockCacheByMeta[meta] = o
        else
            -- utils.print("created again:", meta)
        end
    end
    
    return o
end

local function copyClassHierarchy(classes)
    local ret = OrderedTable()
    for k, v in pairs(classes or {}) do
        ret[k] = v
    end
    return ret
end

function CreateClass(schema, name)
    local ret = {
        Valid = true,
        Children = OrderedTable(),
        Schema = schema,
        FailReasons = {},
        Subclasses = {},
        Name = name
    }
    function ret:AddFailReason(reason, ...)
        self.Valid = false
        table.insert(self.FailReasons, string.format(reason, ...))
    end
    function ret:FlattenInheritancePaths()
        local r = {}
        if not self.Valid then return r end
        if #self.Subclasses == 0 then
            table.insert(r, self.Name or "")
        end
        for _, cl in ipairs(self.Subclasses) do
            local subclPaths = cl:FlattenInheritancePaths()
            for _, s in ipairs(subclPaths) do
                if self.Name then s = self.Name .. "<-" ..s end
                table.insert(r, s)
            end
        end
        return r
    end
 
    function ret:HierarchyAsString()
        if self.Valid ~= true then return "<INVALID_CLASS>" end
        local paths = self:FlattenInheritancePaths()
        local r = ""
        for _, cl in ipairs(paths) do
            if r == "" then r = cl
            else r = r .. ";"..cl end
        end
        return r
    end

    function ret:AddSubclass(class)
        class.Block = self.Block
        table.insert(self.Subclasses, class)
    end

    function ret:isOneOfClasses(classes)
        if self.Valid ~= true then return false end
        for _, cl in ipairs(classes) do
            if self.Name == cl then return true end
        end
        for _, existingClass in ipairs(self.Subclasses) do
            if existingClass:isOneOfClasses(classes) then return true end
        end
        return false
    end

    function ret:visitChildrenByClass(classes, visitor, maxNestingLevel)
        -- TODO USE CAREFULLY, nesting works strange! Need to refactor to have more clear behaviour
        if maxNestingLevel == nil then maxNestingLevel = 1 end
        if type(maxNestingLevel) ~= "number" or maxNestingLevel == 0 then
            return
        end
        if self.Valid ~= true then return end
        for k, v in pairs(self.Children) do
            local kk, vv
            local keyNesting, valueNesting = maxNestingLevel, maxNestingLevel
            if k:isOneOfClasses(classes) then
                kk = k
                keyNesting = keyNesting - 1
            end
            if v:isOneOfClasses(classes) then
                vv = v
                valueNesting = valueNesting - 1
            end
            if kk or vv then
                if visitor(kk, vv) == false then
                    return false
                end
            end
            
            if k:visitChildrenByClass(classes, visitor, keyNesting) == false then
                return false
            end
            if v:visitChildrenByClass(classes, visitor, valueNesting) == false then
                return false
            end
        end
        for _, existingClass in ipairs(self.Subclasses) do
            if existingClass:visitChildrenByClass(classes, visitor, maxNestingLevel) == false then
                return false
            end
        end
    end

    function ret:print(indent)
        if next(self.Children) and self.Name then
            -- print(indent .. " "..self.Name)
        end
        for k, v in pairs(self.Children) do
                    
            k:print(indent .. "  ")
            v:print(indent .. "    ")
        end
        for _, class in ipairs(self.Subclasses) do
            if class.Valid then
                class:print(indent.."      ")
            end
        end
    end

    function ret:hasNamedClasses()
        if self.Valid == false then return false end
        if self.Name then return true end
        for _, cl in ipairs(self.Subclasses) do
            if cl:hasNamedClasses() then
                return true
            end
        end

        return false
    end

    function ret:getChildValueByClass(className)
        if self.Valid ~= true then return end
        for k, v in pairs(self.Children) do
            if v:isOneOfClasses({className}) then return v end
        end
        for _, existingClass in ipairs(self.Subclasses) do
            local r = existingClass:getChildValueByClass(className)
            if r  then
                return r
            end
        end
    end
    return ret
end


function CodeBlock:isOneOfClasses(classes)
    if type(classes) == 'string' then
        classes = {classes}
    end
    for _, existingClass in ipairs(self.Classes) do
        if existingClass:isOneOfClasses(classes) then return true end
    end
    return false
end

function CodeBlock:visitChildrenByClass(classList, visitor, maxNestingLevel)
    for _, existingClass in ipairs(self.Classes) do
        if existingClass:visitChildrenByClass(classList, visitor, maxNestingLevel) == false then return true end
    end
end

function CodeBlock:getChildValueByClass(class)
    for _, existingClass in ipairs(self.Classes) do
        local r = existingClass:getChildValueByClass(class)
        if r then return r end
    end
end
function CodeBlock:CollectChildrenByTextCoord(query, result)
    utils.errorExt("deprecated")
--     надо сделать кэш блоков
-- где в каждом блоке хранить таблицу, где будет список того, чем еще блок мог бы быть
-- то есть когда создаем блок на том же месте, надо не просто плодить, а трекать список на этом месте
    local startOk = false
    local endOk = false

    if self.SrcMeta then
        if self.SrcMeta.srcStart.line < query.line then
            startOk = true
        elseif self.SrcMeta.srcStart.line == query.line and self.SrcMeta.srcStart.column <= query.column then
            startOk = true
        end

        if self.SrcMeta.srcEnd.line > query.line then
            endOk = true
        elseif self.SrcMeta.srcEnd.line == query.line and self.SrcMeta.srcEnd.column >= query.column then
            endOk = true
        end
    elseif self.Parent == nil then
        startOk = true
        endOk = true
    end

    if startOk == true and endOk == true then
        for keyBlock, valueBlock in pairs(self.Children) do
            keyBlock:CollectChildrenByTextCoord(query, result)
            valueBlock:CollectChildrenByTextCoord(query, result)
        end
        table.insert(result, self)
    end

    return result
end


local StatusEntryType = OrderedTable()
StatusEntryType.I = 'Info'
StatusEntryType.W = 'Warning'
StatusEntryType.E = 'Error'


local StatusLogicLevel = {
    TextData = 'Text Data',
    YamlParsing = 'YAML',
    AGSyntax = 'Actiongraph Syntax',
    AGProgram = 'Actiongraph Program'
}

local Module = {
    statuses = {},
    path = "",
}

function Module:addStatus(statusType, logicLevel, message)
    assert(statusType ~= nil)
    assert(logicLevel ~= nil)
    message = message or ""
    assert(type(message) == 'string')
    local st = {
        statusType = statusType,
        logicLevel = logicLevel,
        message = message
    }
    setmetatable(st, { __tostring = function(self)
        return string.format("Status '%s', level '%s': %s", self.statusType, self.logicLevel, self.message)
    end })
    if self.statuses[logicLevel] == nil then self.statuses[logicLevel] = {} end
    table.insert(self.statuses[logicLevel], st)
end



local function parseNumber(block, currentClass)
    if type(block.Content) ~= 'number' then
        currentClass:AddFailReason("Content is not a number")
        return false
    end
    return true
end

local function parseInteger(block, currentClass)
    if type(block.Content) ~= 'number' then
        currentClass:AddFailReason("Content is not a number")
        return false
    end

    if block.Content ~= math.floor(block.Content) then
        currentClass:AddFailReason("Content is not an integer number")
        return false
    end
    return true
end

local function parseConst(block, currentClass)
    if block.Content ~= currentClass.Schema.const then
        currentClass:AddFailReason("Content doesn't match const value")
        return false
    end
    return true
end

local function parseNull(block, currentClass)
    if block.Content ~= SRC_NULL then
        currentClass:AddFailReason("Content is not 'null' value")
        return false
    end
    return true
end

local function parseBoolean(block, currentClass)
    if type(block.Content) ~= 'boolean' then
        currentClass:AddFailReason("Content is not an boolean")
        return false
    end
    return true
end

local function parseString(block, currentClass)
    if type(block.Content) ~= 'string' then
        currentClass:AddFailReason("Content is not a string")
        return false
    end
    if currentClass.Schema.pattern and matchPattern(block.Content, currentClass.Schema.pattern) == nil then
        currentClass:AddFailReason("Content doesn't match a pattern")
        return false
    end
    if currentClass.Schema.minLength and string.len(block.Content) < currentClass.Schema.minLength then
        currentClass:AddFailReason("Content minimal length mismatch")
        return false
    end
    if currentClass.Schema.maxLength and string.len(block.Content) > currentClass.Schema.maxLength then
        currentClass:AddFailReason("Content maximum length mismatch")
        return false
    end
    return true
end

local function parseArray(block, currentClass)
    if type(block.Content) ~= 'table' or block.Content == SRC_NULL or (next(block.Content) and not block.Content[1]) then
        currentClass:AddFailReason("Content is not a list")
        return false
    end
    local childrenSchema = currentClass.Schema.items or {}


    local count = 0
    local finalParseResult = true
    for index, itemValue in ipairs(block.Content) do

        local indexBlock = P.NewCodeBlock(tostring(index), block.Content:GetKeyMeta(index), block)
        local cl = CreateClass({type = "string"})
        cl.Name = "ListIndex"
        indexBlock:AddClass(cl)
        P.parseBlock(indexBlock, cl)
        local childBlock = P.NewCodeBlock(itemValue, block.Content:GetValueMeta(index), block)
        local vcl = CreateClass(childrenSchema)
        childBlock:AddClass(vcl)
        local valid = P.parseBlock(childBlock, vcl)
        if not valid then
            currentClass:AddFailReason("Item %s doesn't match schema", index)
            finalParseResult = false
        end
        currentClass.Children[indexBlock] = childBlock
        count = count + 1
    end

    if currentClass.Schema.minItems and count < currentClass.Schema.minItems then
        currentClass:AddFailReason("Content minimal length mismatch")
        finalParseResult =  false
    end
    if currentClass.Schema.maxItems and count > currentClass.Schema.maxItems then
        currentClass:AddFailReason("Content maximum length mismatch")
        finalParseResult =  false
    end

    return finalParseResult
end

local function parseObject(block, currentClass)
    local finalParseResult = true

    if type(block.Content) ~= 'table' or block.Content == SRC_NULL then
        currentClass:AddFailReason("Content is not a mapping")
        return false
    end

    if currentClass.Schema.required ~= nil then
        for _, req in ipairs(currentClass.Schema.required) do
            if block.Content[req] == nil then
                currentClass:AddFailReason(string.format("No required property '%s'", req))
                finalParseResult = false
            end
        end
    end

    local checkProp = function(propKey)
        if currentClass.Schema.properties then
            local keyBlock = P.NewCodeBlock(propKey, block.Content:GetKeyMeta(propKey), block)
            local cl = CreateClass({type = "string"}, "FixedKeyword")
            keyBlock:AddClass(cl)
            P.parseBlock(keyBlock, cl)
            local keyok = true
            if currentClass.Schema.properties[propKey] == nil and currentClass.Schema.additionalProperties == false then
                currentClass:AddFailReason(string.format("Additional property '%s' not allowed", propKey))
                finalParseResult = false
                local cl = CreateClass()
                keyBlock:AddClass(cl)
                cl:AddFailReason("This additional property not allowed")
                keyok = false
            end
            return keyBlock, currentClass.Schema.properties[propKey] or {}, keyok
        end
        
        if currentClass.Schema.patternProperties ~= nil then
            local keyBlock
            local patternCount = 0
            local patternValueBroken
            local expectedKeySchemasForFailCase = {}
            local keyBlockClassVariant
            for keyPattern, patternSchema in pairs(currentClass.Schema.patternProperties) do
                patternValueBroken = patternSchema
                patternCount = patternCount + 1
                keyBlock = P.NewCodeBlock(propKey, block.Content:GetKeyMeta(propKey), block)
                keyBlockClassVariant = CreateClass({
                    type = 'string',
                    pattern = keyPattern
                })
                keyBlock:AddClass(keyBlockClassVariant)
                
                if keyPattern == "" or type(propKey) == 'string' and matchPattern(propKey, keyPattern) then
                    return keyBlock, patternSchema, true
                end
                table.insert(expectedKeySchemasForFailCase, {
                    type = 'string',
                    pattern = keyPattern
                })
            end
            keyBlockClassVariant.Schema =  { oneOf = expectedKeySchemasForFailCase }
            keyBlockClassVariant:AddFailReason("Doesn't match any of pattern properties")
            if patternCount == 1 then
                return keyBlock,  patternValueBroken, false
            else
                return keyBlock, {}, false
            end
        end

        if currentClass.Schema.keyObjectPatternProperties ~= nil then
            local correctKeys = {}
            local brokenKeys = {}
            local brokenChildrenKeys = {}
            local mapping = {}
            local expectedKeySchemasForFailCase = {}
            local keyBlock
            
            for _, keyObjectPattern in ipairs(currentClass.Schema.keyObjectPatternProperties) do
                local keySchema, patternSchema = keyObjectPattern.keyPattern, keyObjectPattern.valuePattern
                keyBlock = P.NewCodeBlock(propKey, block.Content:GetKeyMeta(propKey), block)
                local cl = CreateClass(keySchema)
                keyBlock:AddClass(cl)
                local ok = P.parseBlock(keyBlock, cl)
                mapping[keyBlock] = patternSchema
                -- if keyBlock.IsBroken then
                --     table.insert(brokenKeys, keyBlock)
                -- else
                if ok ~= true then
                    table.insert(brokenChildrenKeys, keyBlock)
                else
                    table.insert(correctKeys, keyBlock)
                end
                table.insert(expectedKeySchemasForFailCase, keySchema)
            end

            if #correctKeys == 1 then
                return correctKeys[1], mapping[correctKeys[1]], true
            elseif #brokenChildrenKeys == 1 then
                return brokenChildrenKeys[1], mapping[brokenChildrenKeys[1]], false
            elseif #brokenKeys == 1 then
                return brokenKeys[1], mapping[brokenKeys[1]], false
            end
            local class = CreateClass({oneOf = expectedKeySchemasForFailCase})
            keyBlock:AddClass(class)
            class:AddFailReason("Additional properties not allowed")
            if #currentClass.Schema.keyObjectPatternProperties ~= 1 then
                return keyBlock, {}, false
            end
            return keyBlock, currentClass.Schema.keyObjectPatternProperties[1].valuePattern, false
        end
        local keyBlock = P.NewCodeBlock(propKey, block.Content:GetKeyMeta(propKey), block)
        if currentClass.Schema.additionalProperties ~= false then
            return keyBlock, {}, true
        end
        local class = CreateClass({})
        keyBlock:AddClass(class)
        class:AddFailReason("Additional properties not allowed")
        return keyBlock, {}, false
    end
    
    local count = 0
    for propKey, propValue in pairs(block.Content) do
        local keyBlock, childValueSchema, keyBlockOk = checkProp(propKey)
        count = count + 1
        local childBlock = P.NewCodeBlock(propValue,  block.Content:GetValueMeta(propKey), block)
        local kcl = CreateClass(childValueSchema)
        childBlock:AddClass(kcl)
        local ok = P.parseBlock(childBlock, kcl)
        currentClass.Children[keyBlock] = childBlock

        if keyBlockOk ~= true and currentClass.Schema.additionalProperties == false then
            currentClass:AddFailReason("Invalid  key %s", count)
            finalParseResult = false
        end
        if ok ~= true then
            currentClass:AddFailReason("Invalid property %s", count)
            finalParseResult = false
        end
    end

    if currentClass.Schema.minProperties ~= nil and count < currentClass.Schema.minProperties then
        currentClass:AddFailReason("Content minimal length mismatch")
        finalParseResult = false
    end

    if currentClass.Schema.maxProperties ~= nil and count > currentClass.Schema.maxProperties then
        currentClass:AddFailReason("Content minimal length mismatch")
        finalParseResult = false
    end
    return finalParseResult
end


local dispatcher = {
    object = parseObject,
    number = parseNumber,
    integer = parseInteger,
    array = parseArray,
    string = parseString,
    boolean = parseBoolean,
    null = parseNull
}

P.CodeBlockSchemas = {}

for k, v in pairs(languageSchema['$defs']) do
    P.CodeBlockSchemas['#/$defs/' .. k] = {
        Name = k,
        Schema = v
    }
end

local  function parseOneOf(block, currentClass)
    local successCount = 0
    for _, sch in ipairs(currentClass.Schema['oneOf']) do
        local cl = CreateClass(sch)
        currentClass:AddSubclass(cl)
        if P.parseBlock(block, cl) then
            successCount = successCount + 1
        end
       
    end
    if successCount ~= 1 then
        currentClass:AddFailReason("Exactly one schema should match")
        return false
    end
    return true
end

local function parseNotSchema(block, currentClass)
    local cl = CreateClass(currentClass.Schema['not'])
    currentClass:AddSubclass(cl)
    if P.parseBlock(block, cl) then
        currentClass:AddFailReason("Schema matched but should not")
        return false
    end
    return true
end

local function parseAllOfSchema(block, currentClass)
    local hasBroken = false
    for _, sch in ipairs(currentClass.Schema['allOf']) do
        local cl = CreateClass(sch)
        currentClass:AddSubclass(cl)
        if not P.parseBlock(block, cl) then
            hasBroken = true
        end
    end
    if hasBroken then
        currentClass:AddFailReason("Not all schemas are satisfied")
        return false
    end
    return true
end



function P.parseBlock(block, currentClass)
    while currentClass.Schema['$ref'] ~= nil do
        local newSch = P.CodeBlockSchemas[currentClass.Schema['$ref']]
        if currentClass.Name ~= nil then
            local newCl = CreateClass(newSch.Schema, newSch.Name)
            currentClass:AddSubclass(newCl)
            currentClass = newCl
        else
            currentClass.Schema = newSch.Schema
            currentClass.Name = newSch.Name
        end
    end

    local ok = false
    if currentClass.Schema['oneOf'] then
        ok = parseOneOf(block, currentClass)
    elseif currentClass.Schema['not'] then
        ok = parseNotSchema(block, currentClass)
    elseif currentClass.Schema['allOf'] then
        ok = parseAllOfSchema(block, currentClass)
    else
        
        
        if currentClass.Schema['const'] then
            ok = parseConst(block, currentClass)
        elseif dispatcher[currentClass.Schema.type] ~= nil then
            ok = dispatcher[currentClass.Schema.type](block, currentClass)
        else
            if next(currentClass.Schema) == nil then
                ok = true
            else
                errorExt("ERROR IN LANGUAGE SCHEMA")
            end
            
        end
        
        
    end

    return ok
end

function Module:print()
    print("\n#######", self.path)
    if not self.rootCodeBlock then
        print("\tNo parsed entities in module")
    else
        self.rootCodeBlock:print()
    end
end

function Module:BlocksByTextCoordinates(query)
    utils.errorExt("UNIMPLEMENTED")
    if self.rootCodeBlock == nil then return nil end
    local result = {}
    return self.rootCodeBlock:CollectChildrenByTextCoord(query, result)
end

local function NewModule(path, yamlContent)
    path = path_lib.abspath(path)
    -- log("Trying to load to parser: ", path)
    local r = {
        statuses = {},
        path = path,
    }
    setmetatable(r, { __index = Module })

    local readOk, yamlContentRes
    if yamlContent == nil then
        readOk, yamlContentRes = pcall(function() return io.open(path):read("a") end)
        if readOk == true then
            -- log("Successfully read file", path)
        else
            log("Failed to read file", path)
        end
    else
        -- log("Using provided string with yaml content")
        readOk = true
        yamlContentRes = yamlContent
    end
    r.yamlContent = yamlContentRes
    if readOk == false then
        r:addStatus(StatusEntryType.E, StatusLogicLevel.TextData, yamlContentRes)
    else
        local ok, parsedYaml, meta = pcall(function() return lyaml_lib.load(yamlContentRes,
            { add_metainfo = true, src_location = path }) end)
        if not ok then
            r:addStatus(StatusEntryType.E, StatusLogicLevel.YamlParsing, parsedYaml)
        else
            r.rootCodeBlock = P.NewCodeBlock(parsedYaml, meta, nil)
            local class = CreateClass(languageSchema)
            r.rootCodeBlock:AddClass(class)
            P.parseBlock(r.rootCodeBlock, class)
        end
    end
    -- r:print()
    return r
end

function P.SourceCodeParser()
    local ret = {
        updateCallbacks = {},
        modules = OrderedTable()
    }
    setmetatable(ret, { __index = P })
    return ret
end

function P:BlocksByTextCoordinates(path, query)
    path = path_lib.abspath(path)
    if self.modules[path] == nil then
        log("no parsed modules with path", path)
        return nil
    end
    return self.modules[path]:BlocksByTextCoordinates(query)
end

function P:addSourceFromYAMLFile(path, text)
    path = path_lib.abspath(path)
    if self.modules[path] and self.modules[path].yamlContent == text then return end
    self.modules[path] = NewModule(path, text)
    self:notify(path, 'updated')
end

function P:removeSourceByPath(path)
    path = path_lib.abspath(path)
    self.modules[path] = nil
    self:notify(path, 'removed')
end

function P:notify(path, event)
    for c, _ in pairs(self.updateCallbacks) do
        c(path, event)
    end
end

function P:subscribe(clb)
    self.updateCallbacks[clb] = true
end

function P:iterateStatuses(visitor)
    for path, doc in pairs(self.modules) do
        for level, stList in pairs(doc.statuses) do
            for _, st in ipairs(stList) do
                visitor(path, level, st)
            end
        end
    end
end


return P
