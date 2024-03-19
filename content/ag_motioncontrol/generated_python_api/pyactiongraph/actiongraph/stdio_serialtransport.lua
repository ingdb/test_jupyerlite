require"custom_lowlevel_functions"

local io = io
local start_stdin_async_processing= start_stdin_async_processing
local read_stdin=  read_stdin
local stdio_started = false
local scheduler = require"scheduler"
local used = false
function stdio_serialtransport()
    local r = {}
    function r:open()
        if used == true then
            return false
        end
        used = true
        if stdio_started == false then
            stdio_started = true
            start_stdin_async_processing()
        end
        return true
    end

    function r:close()
        used = false
    end

    function r:readData(tm)
        if used == false then 
            error("Not opened")
        end
        local ms = millis()
        while true do
            local data = read_stdin()
            if string.len(data) > 0 then
                return data
            end
            if tm == 0 then
                break
            else
                if type(tm) =="number" then
                    if millis() - ms > tm then break end
                end
                scheduler.sleep(0.001)
            end
        end
    end

    function r:sendData(data)
        if used == false then 
            error("Not opened")
        end
        io.stdout:write(data)
        io.stdout:flush()
    end

    function r:availableConnections()
        return {}
    end
 
    return r
end