local argparse = require "argparse"
local parser = argparse("./lua_interpreter ../actiongraph/mermaid_generator.lua", "ActionGraph graph visualisation tool") 

parser:argument("input", "Main actiongraph source file.")
parser:option("--mermaid", "Output mermaid script for visualisation")
parser:option("--mermaid_depth", "Mermaid max. nesting level")


local arguments = parser:parse(cmd_args)
local actiongraph = require("interpreter")

local ag = actiongraph.LoadActiongraphFromMainFile(arguments.input)

local compiler = require("graph_visualisation").MermaidCompiler()
compiler:run(ag.mainContext, tonumber(arguments.mermaid_depth), arguments.mermaid)
