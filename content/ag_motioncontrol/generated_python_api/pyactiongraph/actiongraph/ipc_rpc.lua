local P = {}   -- package

local json = require'json'
local utils = require("utils")
local pairs = pairs
local table = table
local ipairs =ipairs
local type = type
local require = require
local scheduler = require'scheduler'
local string = string
local _ENV = P



function NewRPCParserSender(transportConfs)
    local ioList = {}
    for _, transportConf in ipairs(transportConfs) do
        local rpcSendFunction, rpcReceiveFunction
        if transportConf == nil then
            rpcSendFunction = function()end
            rpcReceiveFunction = function()end
        elseif type(transportConf) == "string" then
            local external_api_rpc = require'external_api_rpc'
            rpcSendFunction, rpcReceiveFunction = external_api_rpc(transportConf)
        else
            rpcSendFunction, rpcReceiveFunction = transportConf.rpcSendFunction, transportConf.rpcReceiveFunction
        end
        table.insert(ioList, {rpcSendFunction=rpcSendFunction, rpcReceiveFunction = rpcReceiveFunction})
    end
    local r = {
        stdinRPCCallbacks = {}
    }

    function r:addCallback(f)
        table.insert( self.stdinRPCCallbacks, f )
    end

    local readTasks = {}
    for _, ioPair in ipairs(ioList) do
        local rpcReceiveFunction = ioPair.rpcReceiveFunction
        local tsk = scheduler.addTask(function()
            while true do
                local msgs = rpcReceiveFunction()
                local idx = 1
                while true do
                    local m = msgs[idx]
                    if m == nil then
                        break
                    end
                    -- utils.print("RECEIVED RPC: ", json.stringify(m))
                    for _, clb in ipairs(r.stdinRPCCallbacks) do
                        clb(m)
                    end
                    idx = idx + 1
                end         
            end
        end, string.format("rpc '%s' receiving task for io pair '%s'", r, ioPair))
        table.insert(readTasks, tsk)
    end
  
    function r:Send(obj)
        local toSend = {}
        if obj['command'] ~= nil then
            toSend['command'] = obj['command']
        else
            toSend['command'] = "rpc_msg_from_robot"
        end
        for k, v in pairs(obj) do
            toSend[k] = v
        end
        
        for _, ioPair in ipairs(ioList) do
            -- utils.print("HHHERE", json.stringify(toSend))
            ioPair.rpcSendFunction(toSend)
        end
    end
  
    function r:Stop()
        for _, tsk in ipairs(readTasks) do
            tsk.cancel()
        end
    end
    return r
end

return P
