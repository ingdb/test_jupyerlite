local P = {}   -- package

local io = io
local path_lib = require("pl.path")
local dir_lib = require("pl.dir")


local pairs = pairs
local ipairs = ipairs
local error = error
local table = table
local type = type
local ag_utils = require'interpreter.helpers'
local string = string
local log = ag_utils.log

local EMBEDDED_TYPES = {
    Hardware = require'interpreter.embedded_hw_types',
    Graphs = require'interpreter.embedded_node_types'
}

require("interpreter.parameters")
require("interpreter.hw_modules")
require("interpreter.configurations")
require("interpreter.graphs")

local resolveHWType = resolveHWType
local resolveConfType = resolveConfType
local resolveGraphType = resolveGraphType
local NewConfiguration = NewConfiguration

local globalEnv = _ENV
local _ENV = P


local typeResolvers = {
    Hardware = resolveHWType,
    Configurations = resolveConfType,
    Graphs = resolveGraphType
}

function Resolve(entityType, typeName, module_context)
    local embd = EMBEDDED_TYPES[entityType] and EMBEDDED_TYPES[entityType][typeName]
    if embd ~= nil then
        local src = embd()
        return typeResolvers[entityType](src, typeName, module_context)
    end
    if module_context.src_structure.Components == nil or
        module_context.src_structure.Components[entityType] == nil or
        module_context.src_structure.Components[entityType][typeName] == nil then
        return nil
        
    end

    local typeSrc = module_context.src_structure.Components[entityType][typeName]

    return typeResolvers[entityType](typeSrc, typeName, module_context)
end


return P
