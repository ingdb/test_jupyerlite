local P = {}   -- package

local globalEnv = _ENV
local require = require
local _ENV = P


MermaidCompiler = require'graph_visualisation.mermaid_compiler'.NewMermaidCompiler
return P
