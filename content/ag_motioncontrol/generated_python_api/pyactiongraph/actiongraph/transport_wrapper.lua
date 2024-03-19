
local utils = require"utils"
local P = {
    active_connections = {}
}

P.transportFactory = {
    serialport2 = function() require"serialport_serialtransport" return serialport_serialtransport, false end,
    zmq = function() require"zmq_serialtransport" return zmq_serialtransport, true end,
    stdio = function() require"stdio_serialtransport" return stdio_serialtransport, false end
}

function P.SerialTransport()
    local ret = {
        t = nil
    }
    function ret:availableSerialPorts(selector)
        if string.find(selector, "serialport2") ~= nil then
            local serialport = P.transportFactory["serialport2"]()
            local conns = serialport():availableConnections()
            local ret = {}
            for _, t in ipairs(conns) do
                if string.find(t.port, "Bluetooth") == nil then
                    local str = "serialport2="..t.port
                    for k, v in pairs(t) do
                        str = str .. " " .. k .. "="..v
                    end
                    table.insert(ret, str)
                end
            end
            return table.unpack(ret)
        end
        return
    end
    function ret:open(conn)
        self:close()
        local params = {}
        for k, v in string.gmatch(conn, "([^%s]+)=([^%s]+)") do
            params[k] = v
        end
        params.port = params.serialport2 -- compatibility

        for transport_id, factory in pairs(P.transportFactory) do
            if string.find(conn, transport_id) == 1 then
                local constructor, supportsMessages = factory()
                self.t = constructor()
                self.__supportsMessages = supportsMessages
                break
            end
        end
        if self.t == nil then
            utils.errorExt("Unknown transport")
        end
        
        local r = self.t:open(params)
        if r == true then
            P.active_connections[self] = true
        end
        return r
    end
    function ret:close()
        P.active_connections[self] = nil
        if  self.t ~= nil then
            self.t:close()
        end
        self.t = nil
    end
    function ret:readData(...)
        -- utils.print(...)
        return self.t:readData(...)
    end
    function ret:sendData(...)
        -- utils.print(...)
        return self.t:sendData(...)
    end

    function ret:supportsMessages() return self.__supportsMessages end
    return ret
end

function P.shutdown_all()
    for conn, _ in pairs(P.active_connections) do
        if conn.t ~= nil then
            -- utils.print("Closing connection ", conn.t)
            conn.t:close()
        end
    end
    P.active_connections = {}
end
return P