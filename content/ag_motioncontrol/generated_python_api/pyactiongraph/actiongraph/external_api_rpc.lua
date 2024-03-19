local P = {}   -- package

local json = require'json'
local utils = require("utils")
local coromake = require "coroutine.make"
local string = string
local type = type
local table = table
local tonumber = tonumber
local pcall = pcall

-- local globalEnv = _ENV
local coroutine = coromake()
local scheduler = require'scheduler'

return function (transportConfig)
    local SerialTransport = require"transport_wrapper".SerialTransport
    local externalRPCSerialTransport = SerialTransport()
    externalRPCSerialTransport:open(transportConfig)

    if externalRPCSerialTransport:supportsMessages() == true then
        -- utils.print(string.format("Transport '%s' supports messages: %s", transportConfig, externalRPCSerialTransport:supportsMessages()))

        local function STDIOMessagesSender (toSend)
            externalRPCSerialTransport:sendData(json.stringify(toSend))
        end
        local function STDIOMessagesGetter ()
            local data
            while data == nil or string.len(data) == 0 do
                data = externalRPCSerialTransport:readData()
                scheduler.sleep(0.001)
            end          
            -- utils.print(string.format("DATA RECEIVED FROM TRANSPORT '%s': '%s'", transportConfig, json.stringify(data)))
            local ok, res = pcall(function() return json.parse(data) end);
            if ok == true then
                return {res}
            else
                utils.print(string.format("JSON parsing error '%s': '%s'", res, data))
                return {}
            end
        end
        return STDIOMessagesSender, STDIOMessagesGetter
    end

    local function STDIOMessagesSender (toSend)
        local msg = json.stringify(toSend)
        msg = "Content-Length: ".. string.len(msg).."\r\n\r\n"..msg
        externalRPCSerialTransport:sendData(msg)
    end

    local rpcParser = coroutine.create(function()
        local rpcBuf = ""
        while true do
            local contentLengthStart = rpcBuf:find("Content-Length: ", 1, true)
            while contentLengthStart == nil do
                rpcBuf = rpcBuf .. coroutine.yield()
                rpcBuf = rpcBuf:gsub("\13", "")
                contentLengthStart = rpcBuf:find("Content-Length: ", 1, true)
            end
            rpcBuf = rpcBuf:sub(contentLengthStart + string.len("Content-Length: "))
            
            local contentLengthEnd = rpcBuf:find("\n", 1, true)
            
            while contentLengthEnd == nil do
                rpcBuf = rpcBuf .. coroutine.yield()
                rpcBuf = rpcBuf:gsub("\13", "")
                contentLengthEnd = rpcBuf:find("\n", 1, true)
            end
        
            local contentLengthStr = rpcBuf:sub(1, contentLengthEnd-1)
            rpcBuf = rpcBuf:sub(contentLengthEnd + string.len("\n"))
            local toRead = tonumber(contentLengthStr)
            -- utils.print(contentLengthStr)
            if toRead ~= nil then
                while string.len(rpcBuf) < toRead do
                    rpcBuf = rpcBuf .. coroutine.yield()
                end
        
                local toParse = rpcBuf:sub(1, toRead);
                rpcBuf = rpcBuf:sub(toRead+1)

                local ok, res = pcall(function() return json.parse(toParse) end);
                if ok == true then
                    coroutine.yield(res)
                else
                    utils.print("Non-json content in rpc body", res, toParse)
                end
            end
        end
    end)
    coroutine.resume(rpcParser, "");

    local function ParseInput(data)
        local ret = {};
        local _, rpcObj = coroutine.resume(rpcParser, data);
        if rpcObj ~= nil then
            while rpcObj ~= nil do
                if type(rpcObj.command) == "string" then
                    table.insert(ret, rpcObj)
                end
                _, rpcObj = coroutine.resume(rpcParser, "");
            end
        end
        return ret;
    end


    local function STDIOMessagesGetter ()
        while true do
            local data
            while data == nil or string.len(data) == 0 do
                data = externalRPCSerialTransport:readData()
                scheduler.sleep(0.001)
            end          

            if string.len( data ) > 0 then
                local msgs = ParseInput(data)
                if #msgs > 0 then
                    return msgs
                end
            end
        end
    end


    return STDIOMessagesSender, STDIOMessagesGetter
end
