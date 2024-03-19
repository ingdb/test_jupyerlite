require"lua_actiongraph_utils"

local utils = require("utils")
local argparse = require "argparse"
local parser = argparse("./lua_interpreter simulator.lua", "ActionGraph Robot Simulator") 
local pathlib = require'pl.path'
local CreateDispatcher = require"dispatcher"
local externalRPC = require'ipc_rpc'

local scheduler = require'scheduler'
SerialTransport = require"transport_wrapper".SerialTransport

local ui_controls_creator = require'ui_controls'

parser:option("-m --manifest", "Simulator manifest file")
parser:flag("-e --efficiency_mode", "Low perfomance efficient mode (non-realtime simulation)")
parser:option("-p --parameters", "Parameters"):count("*"):args(2)
parser:option("-s --serial", "Robot Serial"):count("1")
parser:option("-f --scripts", "Additional scripts"):count("*"):args(1)
parser:option("--ag_rpc_transport_config", "AG client RPC transport config"):count("*"):args(1)

local arguments = parser:parse(cmd_args)

require'lua_actiongraphvminstance'
utils.print ("ActionGraph VM instance info:")
utils.print("\t build:", actiongraphvminstance.ActionGraphVMGetBuildInfo())
local vmVersion = actiongraphvminstance.ActionGraphVMGetVersion()
utils.print("\t", "version: ", vmVersion.version_major, vmVersion.version_minor)

local SerialNumber
if arguments.serial == nil or type(arguments.serial) ~= "string" or string.len(arguments.serial) ~= 8 then
    utils.errorExt("Serial Number should be 8-bytes robot unique ID")
end
SerialNumber = arguments.serial
if #arguments.ag_rpc_transport_config == 0 then
    arguments.ag_rpc_transport_config = {"stdio"}
end
local rpc = externalRPC.NewRPCParserSender(arguments.ag_rpc_transport_config)
local dispatcher = CreateDispatcher(rpc)
local ui_controls = ui_controls_creator(dispatcher)
local Robot = {
    Params = {},
    Scripts = {}
}

utils.print("Trying to load manifest: ", arguments.manifest)
local manifestPath
local manifest = utils.parseYAMLFile(arguments.manifest or "")

if manifest ~= nil then
    if manifest.Version ~= "1.0" then
        utils.errorExt("Expecting manifest version '1.0'")
    end
    if type(manifest.Robots) ~= "table" or manifest.Robots[SerialNumber] == nil then
        utils.errorExt(string.format("No robot with serial '%s' in manifest", SerialNumber))
    else
        local r = manifest.Robots[SerialNumber]
        Robot.Params = r.Parameters or {}
        Robot.Scripts = {}
        if r.Scripts then
            for _, sp in ipairs(r.Scripts) do
                if pathlib.isabs(sp) then
                    table.insert(Robot.Scripts, sp)
                else
                    table.insert(Robot.Scripts, pathlib.abspath(sp, pathlib.dirname(arguments.manifest)))
                end
            end
        else
            Robot.Scripts = {}
        end
        -- declarativeHAL = declarativeHALParser(manifest.Robots[SerialNumber], dispatcher)
    end
    manifestPath = pathlib.dirname(arguments.manifest)
end

utils.print(string.format("Assembling simulator '%s'", SerialNumber))

if arguments.parameters then
    for _, p in ipairs(arguments.parameters) do
        Robot.Params[p[1]] = p[2]
    end
end
local scripts = {
    "hal_library/timing.lua",
    "hal_library/zmq_serial.lua"
}

if arguments.scripts ~= nil and # arguments.scripts > 0 then
    for _, s in ipairs(arguments.scripts) do
        table.insert(Robot.Scripts, s)
    end
end

for _, relPath in ipairs(Robot.Scripts) do
    if pathlib.isabs(relPath) then
        table.insert(scripts, relPath)
    else
        table.insert(scripts, pathlib.join(pathlib.dirname(pathlib.abspath(arguments.manifest)), relPath))
    end
end

dispatcher.Register_RobotUniqueSerialNumber(function()
    if SerialNumber == "" then
        utils.print("WARNING, using default serial number 00000000")
        return "00000000"
    else
        return SerialNumber
    end
end)

local FinalHAL = dispatcher.FinalHAL

local function prepareHALModuleContext(scriptDirPath)
    local obj = {}

    obj.HAL = FinalHAL
    obj.SerialTransport = SerialTransport
    obj.delay = delay
    obj.print = utils.print
    obj.millis = millis
    obj.string = string
    obj.error = error
    obj.pairs = pairs
    obj.ipairs = ipairs
    obj.math = math
    obj.packValueToBinary = serialiseBinaryRPCargument
    obj.unpackValueFromBinary = parseBinaryRPCargument
    obj.packedToBinaryValueLength = binaryRPCargumentByteLength
    obj.require = require
    obj.table = table
    obj.io = io
    obj.thisScriptPath = scriptDirPath
    obj.manifestPath = manifestPath
    obj.simulator = dispatcher
    obj.tonumber = tonumber
    obj.tostring = tostring

    obj.UI = ui_controls

    return obj
end


for _, n in ipairs(scripts) do
    local hal_file = n

    local HAL = prepareHALModuleContext(pathlib.dirname(n))
    HAL.parameters = Robot.Params
    local HALCode, err = loadfile(hal_file, "bt", HAL)
    if HALCode == nil then
        hal_file = hal_file .. "c"
        HALCode, err = loadfile(hal_file, "bt", HAL)
    end
    if HALCode == nil then
        utils.print(string.format("HAL implementation script '%s' loading error: %s", hal_file, err))
    else
        HALCode()
    end
end

-- FinalHALPlacaholder.SendRawDebugMessage = function(id, data)
--     actiongraph_hal.SendRawDebugMessage(id, data)
-- end
ui_controls.SendUIConfig()

rpc:addCallback(function(req)
    if req and req.command == "simulator_send_ui_config" then
        ui_controls.SendUIConfig()
    end
end) 

actiongraph_hal.SetHAL(FinalHAL)

utils.print("Starting simulation")

actiongraphvminstance.ActionGraphVMStartup()

scheduler.addTask(function() 
    while true do
        actiongraphvminstance.ActionGraphVMTick()
        scheduler.sleep(0)
    end
end, "actiongraphvm main")

scheduler.run(nil, arguments.efficiency_mode ~= true)
