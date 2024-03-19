

local P = {}   -- package

local utils = require("utils")
local OrderedTable = require"orderedtable"
local io = io
local lyaml_lib = require "lyaml"
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local debug = debug
local setmetatable = setmetatable
local type = type
local string = string
local error = error
local table = table

local globalEnv = _ENV
local _ENV = P
VERSION = 1
local interpreter_debug = true

SRC_NULL = lyaml_lib.null
function readSrc(path)
    local yaml_string = utils.checkError(function() 
        return io.open(path):read("a") 
    end)
   
    local raw_structure = utils.checkError(function() 
        return lyaml_lib.load(yaml_string, {add_metainfo=true, src_location=path})
    end)
    -- error(raw_structure.GetValueMeta)
    if raw_structure.ActionGraphVersion == nil then
        error("missing version id")
    end

    if raw_structure.ActionGraphVersion ~= VERSION then
        error(
            string.format( "Unsupported actiongraph version '%s': %s", raw_structure.ActionGraphVersion, raw_structure:GetValueMeta('ActionGraphVersion'):toString())
         
        )
    end
    return raw_structure
end

function log(...)
    if interpreter_debug == true then
    
        local arg = {...}
        local printResult = ""
        for i,v in ipairs(arg) do
            printResult = printResult .. tostring(v) .. "\t"
        end
    
          local info = debug.getinfo(2)
          local filename = info.source:match("[^/\\]*.lua$") or info.short_src
        local line = info.currentline
    
       
        local   message = "["  .. tostring(filename) .. ":" .. tostring(line) .. "]\t" .. printResult
       
        -- write to console
        io.stderr:write( "[ACTIONGRAPH DEBUG] ".. message.."\n")
        io.stderr:flush()
    end
end

function trimString(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function tableEmpty (self)
    for _, _ in pairs(self) do
        return false
    end
    return true
end


function splitByDot(s)
    local res = {}
    for chunk in s:gmatch('([^.]+)') do
        table.insert( res, chunk )
    end
    return res
end
  
function splitDottedPath(s)
    local stepCommand = nil
    if s:sub(1, 2) == ".." then
        s = s:sub(3)
        stepCommand = ".."
    end

    local b, e = s:find(".")
    if b ~= nil then
        if b == 1 then return "", s end
        return s:sub(1, b-1), s:sub(b+1)
    end
    return s
end

Entity = {
    EntityType = function() return "GenericEntity" end,
    Parent = function() return nil end,
    Children = function() return OrderedTable() end,
    ID = function() return "anonymous" end,
    GlobalEntity = function(self, i)  end,
    AliasTarget = function(s) return nil end
}

function Entity:new(o, EntityType, GlobalEntity)
    o = o or {}
    o.EntityType = EntityType
    o.GlobalEntity = GlobalEntity
    setmetatable(o, self)
    self.__index = self

    return o
end

function Entity:__tostring()
    local pld = "no details"
    if type(self.ToString) == "function" then 
        pld =  self:ToString()
    elseif type(self.ToString) == "string" then
        pld = self.ToString
    end
    local id = "anonymous"
    return string.format( "[%s(%s) %s]" , self:ID(), self:EntityType(), pld)
end


function Entity:ResolvePath(path)
    -- log("ResolvePath", "'"..path.."'", self)

    path = path or ""
    if path == "" or path == "." then 
        local at = self:AliasTarget()
        
        if at == nil then 
            return self
        else
            -- log("at", at)
            return self:Parent():ResolvePath(at)
        end
    end
    if path:sub(1, 2) == ".." then 
        if path:sub(3, 4) == ".." then
            path = path:sub(3)
        else
            path = path:sub(2)
        end
        if self:Parent() == nil then 
            log("No parent for ", self)
            return nil
        end

        local at = self:Parent():AliasTarget()
        if at == nil then 
            -- log("here")
            return self:Parent():ResolvePath(path)
        else
            log("here")
            return self:Parent():Parent():ResolvePath(at):ResolvePath(path)
        end

    end

    if path:sub(1, 1) ~= "." then
        local b, e = path:find(".", 1, true)
        local th, rest
        if b ~= nil then
            th, rest = path:sub(1, b-1), path:sub(b)
        else
            th = path
            rest = ""
        end
        -- log(th)
        local glob = self:GlobalEntity(th)
        if glob == nil then
            -- log("Global entity '", th, "' unresolved")
            return nil
        else
            local at = glob:AliasTarget()
            if at == nil then 
                return glob:ResolvePath(rest)
            else
                -- log("at", at)
                return glob:ResolvePath(at):ResolvePath(rest)
            end
        end
       

    end
    path = path:sub(2)
    -- log("here", path, self)
    -- if self.Configuration.Parameters ~= nil then log(self.Configuration.Parameters.brd) end
    local b, e = path:find(".", 1, true)
    local th, rest
    if b ~= nil then
        th, rest = path:sub(1, b-1), path:sub(b)
    else
        th = path
        rest = ""
    end
    local chld = self:Children()
    if chld[th] then
        local at = chld[th]:AliasTarget()
        if at == nil then 
            -- log("here", th, self)
            return chld[th]:ResolvePath(rest)
        else
            -- log("at", at, "rest", rest)
            local t1 = chld[th]:Parent()
            if t1 ~= nil then
                local t2 = t1:ResolvePath(at)
                if t2 ~= nil then
                    return t2:ResolvePath(rest)
                else
                    -- log("Unresolved path", at, "in", t1)
                end
            else
                log("No parent for", chld[th])
            end
            return nil
        end
    else
        -- log("No child ", th, "in", self) --TODO it should not be needed
        return nil
    end
end

function Entity:AbsolutePath()
    if self:Parent() == nil then
        return ""
    else
        return self:Parent():AbsolutePath() .. "." .. self:ID()
    end

end

function currentSourceFilePath()
    local str = debug.getinfo(2).source
    str = str:gsub("\\","/")
    return str:match("@?(.*/)")
end

function actionGraphSrcValueError(src, key, msg)
    error((msg and msg..": " or "")..src:GetValueMeta(key):toString(), 2)
end

function actionGraphSrcKeyError(src, key, msg)
    if src.GetKeyMeta == nil then
        error((msg and msg..": " or "")..string.format("<no src info for key '%s'>", key), 2)
    else
        error((msg and msg..": " or "")..src:GetKeyMeta(key):toString(), 2)
    end
end

return P
