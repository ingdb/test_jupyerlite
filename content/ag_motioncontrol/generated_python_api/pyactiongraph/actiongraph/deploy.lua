-- cmd_args = {
--     "--config", [[{"destination_folder":"/Users/tucher/Downloads/igus-demo-2-deploy","target":["Python"],"obfuscateLua":false}]],
--     '/Users/tucher/delta-sticker/igus-demo-2/main.yaml'
-- }

require"lua_actiongraph_utils"

local utils = require("utils")
utils.trace_info = true

local argparse = require "argparse"
local argparser = argparse("lua_interpreter deploy.lua", "ActionGraph Deployment Tool") 
local path_lib = require("pl.path")
local OrderedTable = require"orderedtable"
local json = require'json'

argparser:argument("input", "Main actiongraph source file.")
argparser:option("-c --config", "Deployment configuration"):count(1)

local arguments = argparser:parse(cmd_args)


utils.print(string.format("Deploying '%s' with config '%s'", arguments.input, arguments.config))

if not path_lib.exists(os.getenv("ACTIONGRAPH_ADDITIONAL_PATHS")) then
    utils.errorExt("Set ACTIONGRAPH_ADDITIONAL_PATHS env. variable to abs. path to 'actiongraph' directory")
end
local ag_path = os.getenv("ACTIONGRAPH_ADDITIONAL_PATHS")
path_lib.chdir(os.getenv("ACTIONGRAPH_ADDITIONAL_PATHS"))

local actionGraphSourceCodeParserModule = require'interpreter'.parser
actionGraphSourceCodeParserModule.usecoloredoutput = false
local parser = actionGraphSourceCodeParserModule.SourceCodeParser()
local Linker = require'interpreter'.linker.ProgramLinker

local linker = Linker(
    function(path)
		path = path_lib.abspath(path)
        if parser.modules[path] ~= nil then
            return parser.modules[path]
        end
        parser:addSourceFromYAMLFile(path)
        return parser.modules[path]
    end,
	function()
        return os.getenv("ACTIONGRAPH_PACKAGE_SEARCH_PATH")
    end
)

local config

local ok, res = pcall(function() return json.parse(arguments.config) end)
if ok == true and res ~= nil then
    config = res
else
    utils.errorExt("Cannot parse JSON:", res, arguments.config)
    return
end

linker:AddModule(arguments.input)
linker:Build(arguments.input)

local modulesPaths, lua_scripts = linker:CollectSourceCodeFilesPaths()
local commonPrefix = nil
local packagesPath
if os.getenv("ACTIONGRAPH_PACKAGE_SEARCH_PATH") ~= nil then
    packagesPath = path_lib.normpath(path_lib.abspath(os.getenv("ACTIONGRAPH_PACKAGE_SEARCH_PATH")))
end

local packagesPaths = {}
local userPaths = {}
-- utils.print("MODULES:")
for _, p in ipairs(modulesPaths) do
    if packagesPath ~= nil and path_lib.common_prefix(packagesPath, p) == packagesPath then
        table.insert(packagesPaths, path_lib.relpath(p, packagesPath))
    else
     
        if commonPrefix == nil then
            commonPrefix = path_lib.dirname(p)
        end
        commonPrefix = path_lib.common_prefix (commonPrefix, p)
        table.insert(userPaths, p)
    end
   
    -- utils.print(m.path)
end
-- utils.print("SCRIPTS:")
for _, scrPath in ipairs(lua_scripts) do   
    if packagesPath ~= nil and path_lib.common_prefix(packagesPath, scrPath) == packagesPath then
        table.insert(packagesPaths, path_lib.relpath(scrPath, packagesPath))
    else
        commonPrefix = path_lib.common_prefix (commonPrefix, scrPath)

        table.insert(userPaths, scrPath)
    end
end

-- utils.print("COMMON PREFIX: ", commonPrefix)


local relUserPaths = {}
local mainFile
for _, userPath in ipairs(userPaths) do
    if path_lib.abspath(arguments.input) == userPath then
        mainFile = path_lib.relpath(userPath, commonPrefix)
    end
    table.insert(relUserPaths, path_lib.relpath(userPath, commonPrefix))
end
-- utils.print("mainFile", mainFile)
utils.print("Final package paths")
for _, p in ipairs(packagesPaths) do
    utils.print("PACKAGE PATH", p)
end


utils.print("Final user paths")
for _, p in ipairs(relUserPaths) do
    utils.print("USER PATH", p)
end

local pl_dir = require"pl.dir"

local function copySourceTree(destination_folder)
    pl_dir.makepath(destination_folder)
    pl_dir.makepath(path_lib.join(destination_folder, "actiongraph_packages"))
    pl_dir.makepath(path_lib.join(destination_folder, "src"))

    for _, p in ipairs(packagesPaths) do
        -- utils.print("from", path_lib.join(packagesPath, p))
        -- utils.print("to", path_lib.join(destination_folder, "actiongraph_packages", p))
        pl_dir.makepath(path_lib.dirname(path_lib.join(destination_folder, "actiongraph_packages", p)))
        local ok, err = pl_dir.copyfile(path_lib.join(packagesPath, p), path_lib.join(destination_folder, "actiongraph_packages", p))
        if ok == false then
            utils.errorExt(err)
        end
    end

    for _, p in ipairs(relUserPaths) do
        pl_dir.makepath(path_lib.dirname(path_lib.join(destination_folder, "src", p)))
        local ok, err = pl_dir.copyfile(path_lib.join(commonPrefix, p), path_lib.join(destination_folder, "src", p))
        if ok == false then
            utils.errorExt(err, path_lib.join(commonPrefix, p), path_lib.join(destination_folder, "src", p))
        end
        -- utils.print("USER PATH", p)
    end

end

local lfs = require"lfs"
local delete = require("pl.file").delete

local function compilefiles (path)
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." then
            local f = path_lib.join(path, file)
            local attr = lfs.attributes (f)

            if attr.mode == "directory" then
                compilefiles (f)
            else
                if path_lib.extension(file) == ".lua" then
                    compile_file_to_bytecode(f, f.."c")
                    delete(f)
                end
            end
        end
    end
end

local function copyDir(path, dest_path)
    -- utils.print("copyDir(path, dest_path)", path, dest_path)
    pl_dir.makepath(dest_path)
    for pathname, is_dir in pl_dir.dirtree(path) do
        local relPath = path_lib.relpath (pathname, path)
        local destFPath = path_lib.join(dest_path, relPath)
        if is_dir then
            pl_dir.makepath(destFPath)
            -- utils.print("Creating dir: ", destFPath)
        else
            local ok, err = pl_dir.copyfile(pathname, destFPath)
            if ok == false then
                utils.errorExt("Cannot copy",pathname, destFPath, err)
            end
            -- utils.print(string.format("Copying from '%s' to '%s'", pathname, destFPath))
        end
        
    end
end

local interpreter_dir_mapping = {
    CLI_Linux_x86_64 = "linux-x86_64",
    CLI_Linux_aarch64 = "linux-aarch64",
    CLI_Windows = "windows",
    CLI_MacOS_arm64 = "macos",
    CLI_MacOS_x86_64 = "macos_x86",
}

local startup_script_templates = {
    CLI_Windows = {
        filename = "start.bat",
        text = [[
@echo off
chdir /d %~dp0
set ACTIONGRAPH_ADDITIONAL_PATHS=%~dp0actiongraph
set ACTIONGRAPH_PACKAGE_SEARCH_PATH=%~dp0actiongraph_packages
@echo on
.\lua_interpreter\lua_interpreter.exe actiongraph\cli.lua ..\src\]] .. mainFile:gsub("/", "\\") .. [[ %*]]
    },
    CLI_MacOS_arm64 = {
        filename = "start.sh",
        text = [[
#!/bin/bash
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd $SCRIPT_DIR
export ACTIONGRAPH_ADDITIONAL_PATHS="$SCRIPT_DIR/actiongraph"
export ACTIONGRAPH_PACKAGE_SEARCH_PATH="$SCRIPT_DIR/actiongraph_packages"
./lua_interpreter/lua_interpreter actiongraph/cli.lua ../src/]] .. mainFile:gsub("\\", "/") .. [[ "$@"]]
    },
}

startup_script_templates.CLI_Linux_x86_64 = startup_script_templates.CLI_MacOS_arm64
startup_script_templates.CLI_Linux_aarch64 = startup_script_templates.CLI_MacOS_arm64
startup_script_templates.CLI_MacOS_x86_64 = startup_script_templates.CLI_MacOS_arm64

local function create_python_api(entities, pkg_path)
    local f <close> = assert(io.open(path_lib.join(pkg_path, "__init__.py"), "wb"))
    local function L(text, ...)
        local args = {...}
        if #args > 0 then
            text = string.format(text, ...)
        end
        f:write(text.."\n")
    end
    local function P(s) 
        local replaced , _ = string.gsub(s, "%W", "_")
        return replaced
    end

    local robot_ids = {}
    for robot_id, _ in pairs(entities) do
        table.insert(robot_ids, P(robot_id))
    end
    L("from os import path")
    L("from .pyactiongraph.launcher import APIBase, RobotBase, IncomingEvent, OutgoingEvent, Parameter")
    L("")
    L("class API(APIBase):")
    L("")
    L("    def __init__(self,")
    for _, robot_id in ipairs(robot_ids) do
    L("            "..robot_id.."_serial_number=None,")
    L("            "..robot_id.."_manual_transport=None,")
    L("            "..robot_id.."_additional_simulator_rpc_connections=[],")
    end
    L("            additional_client_rpc_connections=[],")
    L("            debug_logging=False,")
    L("            force_reset=False,")
    L("            simulation=False):")
    L("        super().__init__(")
    L('            path.join(path.dirname(path.abspath(__file__)), "%s"),', path_lib.join("src", mainFile):gsub("\\", "/"))
    L('            package_search_path=path.join(path.dirname(path.abspath(__file__)), "actiongraph_packages"), ')
    L("            manual_transport_configs = [")
    for _, robot_id in ipairs(robot_ids) do
    L("                (%s_serial_number, %s_manual_transport,),", robot_id, robot_id)
    end
    L("            ],")
    L("            robot_serials_override = [")
    for _, robot_id in ipairs(robot_ids) do
    L("                ('%s', %s_serial_number,),", robot_id, robot_id)
    end
    L("            ],")
    L("            additional_client_rpc_connections=additional_client_rpc_connections,")
    L("            additional_simulator_rpc_connections={")
    for _, robot_id in ipairs(robot_ids) do
    L("                '%s': %s_additional_simulator_rpc_connections,", robot_id, robot_id)
    end
    L("            },")    
    L("            debug_logging=debug_logging,")
    L("            force_reset=force_reset,")
    L("            simulation=simulation,")
    L("        )")
    for _, robot_id in ipairs(robot_ids) do
    L("        self.%s = None", robot_id)
    end
    L("")
    L("    def start(self):")
    L("        super().start()")
    for _, robot_id in ipairs(robot_ids) do
    L("        self.%s = Robot_%s(self)", robot_id, robot_id)
    end
    L("")
    L("")
    for id, ent_list in pairs(entities) do
        local robot_id = P(id)
    L("class Robot_%s(RobotBase):", robot_id)
    L("")
    L("    def __init__(self, api) -> None:")
    L('        super().__init__("%s", api)', robot_id)
    L("")
        local eventNames = {}
        for k, entity in pairs(ent_list.incomingEvents or {}) do
            local eventName = P(entity.agAPIPath)
            if entity.eventName and #entity.eventName > 0 and eventNames[entity.eventName] == nil then eventName = P(entity.eventName); eventNames[entity.eventName] = true end
            local eventPostfix = ""
            if eventName:sub(-5, -1):lower() ~= "event" then eventPostfix = "_event" end
    L('        self.%s%s = OutgoingEvent(self, "%s")', eventName, eventPostfix, entity.agAPIPath)
        end
    L("")
        for k, entity in pairs(ent_list.outgoingEvents or {}) do
            local eventName = P(entity.agAPIPath)
            if entity.eventName and #entity.eventName > 0 and eventNames[entity.eventName] == nil then eventName = P(entity.eventName); eventNames[entity.eventName] = true end
            local eventPostfix = ""
            if eventName:sub(-5, -1):lower() ~= "event" then eventPostfix = "_event" end
    L('        self.%s%s = IncomingEvent(self, "%s")', eventName, eventPostfix, entity.agAPIPath)
        end
    L("")
        for k, entity in pairs(ent_list.mutableParameters or {}) do
            local paramName = P(entity.agAPIPath)
    L('        self.%s_param = Parameter(self, "%s")', paramName, entity.agAPIPath)
        end
    L("")
    L("")
    end

end
for _, api_type in ipairs(config.target) do
    local destPath = path_lib.join(path_lib.abspath(config.destination_folder), api_type)
    pcall(function()pl_dir.rmtree (destPath)end)

    if api_type:sub(1,3) == "CLI" then
        copyDir(
            path_lib.abspath(ag_path),
            path_lib.join(destPath, "actiongraph")
        )
        copyDir(
            path_lib.abspath(path_lib.join(ag_path, "../lua_interpreter", interpreter_dir_mapping[api_type])),
            path_lib.join(destPath, "lua_interpreter")
        )

        copySourceTree(destPath)

        if config.obfuscateLua then

            compilefiles (destPath)
        end
        local f <close> = assert(io.open(path_lib.join(destPath, startup_script_templates[api_type].filename), "wb"))
        f:write(startup_script_templates[api_type].text)
    end
end

for _, api_type in ipairs(config.target) do
    if api_type == "Python" then
        local destPath = path_lib.join(path_lib.abspath(config.destination_folder), api_type)
        local function P(s) 
            local replaced , _ = string.gsub(s, "[^%w]+", "_")
            return replaced
        end
        local pkg_name = P(path_lib.basename(commonPrefix))
        local pkg_path = path_lib.join(destPath, pkg_name)
        pl_dir.makepath(pkg_path)
        copySourceTree(pkg_path)
        copyDir(
            path_lib.abspath(path_lib.join(ag_path, "..", "pyactiongraph")),
            path_lib.join(pkg_path, "pyactiongraph")
        )
        copyDir(
            path_lib.abspath(ag_path),
            path_lib.join(pkg_path, "pyactiongraph", "actiongraph")
        )
        copyDir(
            path_lib.abspath(path_lib.join(ag_path, "../lua_interpreter")),
            path_lib.join(pkg_path, "pyactiongraph", "lua", "lua_interpreter")
        )
        copyDir(
            path_lib.abspath(path_lib.join(ag_path, "../simulator")),
            path_lib.join(pkg_path, "pyactiongraph", "simulator")
        )


        copyDir(
            path_lib.join(path_lib.dirname(path_lib.abspath(arguments.input)), "simulation"),
            path_lib.join(pkg_path, "src/simulation")
        )
        copyDir(
            path_lib.join(path_lib.dirname(path_lib.abspath(arguments.input)), "visualisation"),
            path_lib.join(pkg_path, "src/visualisation")
        )
        if config.obfuscateLua then
            compilefiles (pkg_path)
        end
        
        local interactableEntities= linker:CollectInteractableEntities()
        -- utils.print(json.stringify(interactableEntities))
        
        create_python_api(interactableEntities, pkg_path)
    end
end
