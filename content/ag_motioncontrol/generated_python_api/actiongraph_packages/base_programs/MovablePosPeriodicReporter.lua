
actiongraph.EventHandler(actiongraph.ContextGraphPath..".reporter.event", function(args)
    actiongraph.SendHostRPC({rpc_name = "MOVABLE_STATUS", args = args, robot_id = actiongraph.RobotID()}) 
end)
