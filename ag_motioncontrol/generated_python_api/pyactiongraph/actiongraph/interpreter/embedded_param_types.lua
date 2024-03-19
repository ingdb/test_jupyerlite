local P = {}   -- package


local io = io

local path_lib = require("pl.path")
local dir_lib = require("pl.dir")


local pairs = pairs
local ipairs = ipairs
local error = error
local table = table

local globalEnv = _ENV
local _ENV = P


return P
