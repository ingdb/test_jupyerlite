local utils = require("utils")
require'custom_lowlevel_functions'
local function GetUserScriptContext() 
    local C = {}
    C.print = utils.print
    C.ipairs = ipairs
    C.pairs = pairs
    C.millis = millis
    C.require = require
    C.Vector = require'vector'
    C.pcall = pcall
    C.error = error
    C.type = type
    C.table = table
    C.tonumber = tonumber
    C.tostring = tostring
    C.string = string
    C.packValueToBinary = serialiseBinaryRPCargument
    C.unpackValueFromBinary = parseBinaryRPCargument
    C.packedToBinaryValueLength = binaryRPCargumentByteLength
    C.math = math
    return C
end


return GetUserScriptContext