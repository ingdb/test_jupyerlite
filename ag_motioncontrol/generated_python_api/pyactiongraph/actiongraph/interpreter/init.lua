local P = {}   -- package


-- Import Section:
-- declare everything this package needs from outside
-- local io = io

-- local path_lib = require("pl.path")
-- local dir_lib = require("pl.dir")
-- local pairs = pairs
-- local ipairs = ipairs
-- local error = error
-- local table = table

local ag_utils = require'interpreter.helpers'
local NewPackageContext = require'interpreter.package_context'.NewPackageContext
P.LegacyGraphLoader = require'interpreter.legacy_translator'.NewLegacyTranslator
P.GetUserScriptContext = require'interpreter.user_script_context'
P.GetUserScriptRobotAPI = require'interpreter.user_script_robot_api'
P.UserScriptUIAPICreator = require'interpreter.user_script_ui_api'

P.parser = require'interpreter.source_code_parser'
P.linker = require'interpreter.program_linker'
local log = ag_utils.log
local ipairs = ipairs
local pairs = pairs

local globalEnv = _ENV
local _ENV = P


function LoadActiongraphFromMainFile(path, PACKAGE_PATHS)
    local mainContext = NewPackageContext(path, nil, PACKAGE_PATHS)
    mainContext:instantiateRobots()
    local ag = {
        mainContext = mainContext
    }

    return ag
end


return P
-- to create safe execution context, use https://www.lua.org/pil/15.4.html
-- (global env changing). Just need to keep "math" here and add __index metamethod for params resolving
-- "a + b - 1"



