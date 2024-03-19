local P = {}
local base64=require'base64'
require"custom_lowlevel_functions"
local serialiseBinaryRPCargument = serialiseBinaryRPCargument
local parseBinaryRPCargument = parseBinaryRPCargument
local binaryRPCargumentByteLength = binaryRPCargumentByteLength
local ipairs = ipairs
local string = string
local pcall = pcall
local OrderedTable = require'orderedtable'
local table = table
local utils = require"utils"
local type = type
local _ENV = P


function RPC(inputs, outputs)
    local rpc = {
        outputs = outputs,
    }

    function rpc.send(sendFunc, name, values)
        values = values or {}
        local sender = rpc.outputs[name]
        if sender == nil then
            return false, string.format("No output RPC: '%s'", name)
        end
        local args = sender[2]
        local to_send = "" .. serialiseBinaryRPCargument(sender[1], "ui1")
        
        for _, argg in ipairs(args) do 
            local val = values[argg[1]]
            if val == nil then 
                return false, argg[1].." is missing in RPC call '" .. name.."'"
            end
            to_send = to_send .. serialiseBinaryRPCargument(val, argg[2])
        end
    
        local encoded = string.char (2).. base64.encode( to_send )..string.char (3)
    
        sendFunc(encoded)
        return true
        -- if mc.debug_serial then
        --     io.stderr:write("send: ", #encoded, " ", encoded, " ")
        --     for c in to_send:gmatch"." do
        --         io.stderr:write(string.format('%02X ', string.byte(c)))
        --     end
        --     io.stderr:write("\n")
        -- end
    end

    local r = rpc
    r.rpc_rcv_state = 0
    r.rpc_buf = ""
    r.rpc_handlers_table = inputs

    function r.handleMsg(decodedData)
        local rpc_id = decodedData:sub(1, 1)
        local h_list = r.rpc_handlers_table[rpc_id]
        if h_list ~= nil then
            for _, h in ipairs(h_list) do
                if h.data_length == #decodedData then 
                
                    local offset = 2

                    local args = OrderedTable()
                    for _, arg_p in ipairs(h.args_parsers) do 
                        local l
                        args[arg_p.name], l = arg_p.parser(decodedData:sub(offset))
                        offset = offset + l
                    end

                    h.handler(args)
                else
                    -- utils.print(string.format("RPC SIGNATURE MISMATCH: rpc id %s, expected data length %s, got %s", string.byte(rpc_id), h.data_length, #decodedData))
                end
            end
        else
            -- utils.print("UNKNOWN RPC id = ", string.byte(rpc_id))
        end
    end

    function r.addRawData(data)
        r.rpc_buf = r.rpc_buf..data
        for msg_base64 in r.rpc_buf:gmatch("%b\x02\x03") do
            local decodedData = ""
            local st, err = pcall(function() decodedData = base64.decode( msg_base64 ) end)
            if st == true then
                r.handleMsg(decodedData)
            else
                utils.print("ERROR IN BASE64 INCOMING RPC msg")
            end
        end
        local index = r.rpc_buf:match'^.*()\x03'
        if type(index) == "number" then
            r.rpc_buf = r.rpc_buf:sub(index + 1)
        end
        if #r.rpc_buf > 10000 then
            r.rpc_buf = ""
        end
    end



    return rpc
end

function parseRPCEndpoints(endpoints)
    local ret = {}

    for i, h in ipairs(endpoints) do
        local args = h[2]

        local sig = string.char(h[1])
        local args_p = {}
        local args_data_length = 0
        for _, arg_data in ipairs(args) do
            local arg_name, arg_type = arg_data[1], arg_data[2]

            local arg_bin_size = binaryRPCargumentByteLength(arg_type)
            args_data_length = args_data_length + arg_bin_size
            table.insert(args_p, {name=arg_name, parser=function(data) 
                return parseBinaryRPCargument(data, arg_type), arg_bin_size
            end})
        end
        args_data_length = args_data_length + 1
        local t = {}
        t.args_parsers = args_p
        t.data_length = args_data_length
        t.handler = h[3]
        if ret[sig] == nil then  ret[sig] = {} end
        table.insert(ret[sig], t)
    end
    return ret
end

return P