require"lua_actiongraph_utils"

local utils = require("utils")
utils.trace_info = true

local argparse = require "argparse"
local path_lib = require("pl.path")
local OrderedTable = require"orderedtable"
local json = require'json'
local actiongraph = require("interpreter")
local externalRPC = require'ipc_rpc'
local scheduler = require'scheduler'
local commonRPCAPICreator = require"cli_rpc_api"
local mc = require("machine_control")




local function CreateActionGraphClient(arguments)
    local AGClient = {}
    AGClient.rpc = externalRPC.NewRPCParserSender(arguments.ag_rpc_transport_config)

    local ag = actiongraph.LoadActiongraphFromMainFile(arguments.input, arguments.ACTIONGRAPH_PACKAGE_SEARCH_PATH)

    local robotIDToSerialMap = {}
    for _, p in ipairs(arguments.fixed_connections) do
        robotIDToSerialMap[p[1]] = p[2]
    end

    local robotIDToSerialIDMap = {}
    for _, p in ipairs(arguments.serial_ids) do
        robotIDToSerialIDMap[p[1]] = p[2]
    end

    local userScriptsList = {}
    local robotsContexts = OrderedTable()

    ag.mainContext:iterateUserScripts(function(scriptPath, graph, robotId)
        if path_lib.isabs(scriptPath) ~= true then
            scriptPath = path_lib.abspath(path_lib.join(path_lib.dirname(arguments.input), scriptPath))
        end

        table.insert( userScriptsList, {
            path = scriptPath,
            parentGraphPath = graph and "Graph"..graph:AbsolutePath() or nil,
            robotID = robotId
        } )
    end)
    local commonRPCAPI = commonRPCAPICreator(AGClient.rpc)

    local commonRpcDspt = commonRPCAPI.dispatcher(ag.mainContext.Robots)
    AGClient.rpc:addCallback(function(...)
        -- utils.info(5, string.format("Received common rpc in client %s", AGClient))
        return commonRpcDspt(...)
    end)

    local UserScriptUIAPI = actiongraph.UserScriptUIAPICreator(AGClient.rpc)
    local robotsHWInfo = {}

    local hasRobots = false
    for robotId, robot in pairs(ag.mainContext.Robots) do
        if robotIDToSerialIDMap[robotId] ~= nil then
            robot.Serial = robotIDToSerialIDMap[robotId]
            utils.info(5, string.format("Redefined Serial for robot '%s' to '%s'", robotId, robot.Serial ))
        end
        
        local lowlevelAGAPI = mc.CreateRobot(robotId, robot.Serial, robotIDToSerialMap[robot.Serial], arguments.force==true)
        utils.info(10, "Generating ActionGraph VM code for robot '", robotId, "'...")
        local loader = actiongraph.LegacyGraphLoader(robot, lowlevelAGAPI)
        loader:run()
        utils.info(10, "Done Generating ActionGraph VM code for robot '", robotId, "':", json.stringify(lowlevelAGAPI:ByteCodeStats()))
        robotsHWInfo[robotId] = {
            hw_list = lowlevelAGAPI:getHardwareList(),
            -- transportConfig = transportConfig, 
            robot_id = robotId,
            Serial = robot.Serial
        }
        
        robotsContexts[robotId] = {
            robotAPI = actiongraph.GetUserScriptRobotAPI(robot, lowlevelAGAPI),
            loader = loader,
            lowlevelAGAPI = lowlevelAGAPI,
            uiAPI = UserScriptUIAPI.GetAPI(robot),
        }
        lowlevelAGAPI:SetReadyCallback(function()
            -- lowlevelAGAPI:startTimingInstrumentation() --TODO remove later
        end)
        hasRobots = true
    end

  
    if hasRobots ~= true then
        utils.errorExt("No robots defined in this file")
    end


    AGClient.rpc:addCallback(function(req)
        if req and req.command == "request_hwlist" then
            AGClient.rpc:Send({command="robot_hw_list_ready", robots=robotsHWInfo, root_project_path=path_lib.dirname(path_lib.abspath(arguments.input))})
        end
    end)

    function AGClient.ChangeRobotTransport(id, transport)
        scheduler.addTask(function() 
            if robotsContexts[id] then
                robotsContexts[id].lowlevelAGAPI:SetFixedTransport(transport)
            end
        end)
    end
    AGClient.rpc:addCallback(function(msg)
        if msg.command == "change_transport_configs" then
            for robotID, conf in pairs(msg.new_transport_configs) do
                AGClient.ChangeRobotTransport(robotID, conf.transport)
            end
            -- utils.print(json.stringify(msg))
        else
            -- utils.print(json.stringify(msg))
        end
    end)

   
    for _, userScript in ipairs(userScriptsList) do
        local UserHandlersContext = actiongraph.GetUserScriptContext()
        local userScriptPath = userScript.path
        local contextGraphPath = userScript.parentGraphPath
        utils.info(10, string.format( "Handling script '%s' for context '%s' for robot '%s'", userScriptPath, contextGraphPath, userScript.robotID or "nil"))

        UserHandlersContext.actiongraph = {
            Robot = function(id)
                return robotsContexts[id].robotAPI
            end,
            RobotUI = function(id)
                return robotsContexts[id].uiAPI
            end,
        }
        if userScript.robotID ~= nil then
            for k, v in pairs(robotsContexts[userScript.robotID].robotAPI) do
                UserHandlersContext.actiongraph[k]=v
            end
            UserHandlersContext.UI = robotsContexts[userScript.robotID].uiAPI
        end
        UserHandlersContext.actiongraph.ContextGraphPath = contextGraphPath
        UserHandlersContext.actiongraph.CurrentScriptPath = userScriptPath
        UserHandlersContext.actiongraph.MainActionGraphModuleDirPath = ag.mainContext.dir_path

        for k, v in pairs(commonRPCAPI.api(userScript.robotID)) do
            UserHandlersContext.actiongraph[k]=v
        end

        local UserHandlersCode, err = loadfile(userScriptPath, "bt", UserHandlersContext)
        if UserHandlersCode == nil then
            userScriptPath = userScriptPath .. "c"
            UserHandlersCode, err = loadfile(userScriptPath, "bt", UserHandlersContext)
        end
        if UserHandlersCode == nil then
            error("Script loading error: "..path_lib.abspath(userScriptPath)..": "..tostring(err))
            return
        end
        UserHandlersCode()
    end

    AGClient.rpc:addCallback(function(req)
        if req and req.command == "request_ui_conf" then
            UserScriptUIAPI.SendUIConfig()
        end
    end)

    require('lfs').chdir(path_lib.dirname(arguments.input)) -- FIXME: if we have multiple independent client instances, this would interfere. 

    function AGClient.CreateScriptingContext(robotID)
        local ctx = {}
        for k, v in pairs(robotsContexts[robotID].robotAPI) do
            ctx[k]=v
        end
        return ctx
    end

    function AGClient.GetRobotsSerialInfo()
        return robotsHWInfo
    end

    function AGClient.Shutdown()
        AGClient.rpc:Stop()
        for k, v in pairs(robotsContexts) do
            v.lowlevelAGAPI:Shutdown()
            utils.info(10, "AGClient.Shutdown() called")
        end
    end

    return AGClient
end


if DO_NOT_RUN_AG_LOOP == nil then
    local function parseArgs(command_line_argument_list) 
        local parser = argparse("./lua_interpreter ../actiongraph/cli.lua", "ActionGraph CLI") 
        parser:argument("input", "Main actiongraph source file.")
        parser:option("-c --fixed_connections", "Robots connection strings"):count("*"):args(2)
        parser:flag("-f --force", "Overwrite program if any is stored")
        parser:option("--ag_rpc_transport_config", "AG client RPC transport config"):count("*"):args(1)
        parser:option("-s --serial_ids", "Robots id to board serial id"):count("*"):args(2)
        
        return parser:parse(command_line_argument_list)
    end
    local arguments = parseArgs(cmd_args)
    arguments.ACTIONGRAPH_PACKAGE_SEARCH_PATH = os.getenv("ACTIONGRAPH_PACKAGE_SEARCH_PATH")
    if #arguments.ag_rpc_transport_config == 0 then
        arguments.ag_rpc_transport_config = {"stdio"}
    end

    CreateActionGraphClient(arguments)
    scheduler.run()
else
    return {CreateActionGraphClient=CreateActionGraphClient}
end
