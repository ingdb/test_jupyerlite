SerialTransport = require"transport_wrapper".SerialTransport

local utils = require("utils")
utils.trace_info = true

local mc = require("machine_control")
local scheduler = require"scheduler"

local args = {}
for _, kv in ipairs(cmd_args) do
    local ind = kv:find("=")
    args[kv:sub(1, ind-1)] = kv:sub(ind+1)
    
end
local args_ok = true
if args["fw_bin_file"] == nil then 
    utils.print("path to fw bin file should be provided as 'fw_bin_file=PATH' argument")
    args_ok = false
end

if args["force"] ~= "true" and args["version_file"] == nil then 
    utils.print("path to version file should be provided as 'version_file=PATH.h' argument")
    args_ok = false
end
if args_ok == false then
    error("required params missing")
end

local t = SerialTransport()

function readData(timeout)
    delay(timeout)
    return t:readData() or ""
end

function FindActiveBootloader()
    local availableConnections = {}
    if args["conn"] == nil then 
        availableConnections = {t:availableSerialPorts("serialport2")}
    else
        utils.print("Using manually set port", args["conn"])
        availableConnections = {args["conn"]}
    end
    if #availableConnections == 0 then 
        return nil
    end
    for i, config in ipairs(availableConnections) do
        if t:open(config) == true then
            t:sendData("v")
            local bootloader_answer = readData(2000)
            if string.find(bootloader_answer, "Bootloader 1.0") ~= nil then
				
                return config
            end
            t:close()
        end
    end
    return nil
end

function FindFirmware()
    local robot = mc.CreateRobot("r", args["serialnumber"] , args["conn"], false, args["serialnumber"] or true)
    local ts = millis()

    scheduler.run(function()
        return millis() - ts < 3000 and robot.isConnected == false
    end)
    local connection
    if robot.isConnected then
        connection = robot.currentConnection
    else
        return nil
    end


    utils.print("running version info:")
    local running_version_info = robot:ConnectedRobotVersionInfo()
    for k, v in pairs(running_version_info) do
        utils.print("\t"..k, v)
    end

    if args["force"] ~= "true" then
        local update_sw_major_ver = nil
        local update_sw_minor_ver = nil

        for line in io.lines(args["version_file"]) do 
            local b, e = line:find("#define SW_MAJOR_VERSION_GLOBAL_MACRO ")
            if e ~= nil then update_sw_major_ver = tonumber(line:sub(e)) end

            local b, e = line:find("#define SW_MINOR_VERSION_GLOBAL_MACRO ")
            if e ~= nil then update_sw_minor_ver = tonumber(line:sub(e)) end
        end

        if running_version_info.sw_major_version == update_sw_major_ver and running_version_info.sw_minor_version == update_sw_minor_ver then 
            robot:Disconnect()
            return "up_to_date"
        end
    else
        utils.print("Doing forced update")
    end

    utils.print("rebooting into bootloader...")

    robot:RebootToBootloader()
    delay(1000)
    robot:Disconnect()
    
    utils.print("done")
    utils.print("reopening the port", connection)
    t:close()
    delay(1000)
    if t:open(connection) == false then
        return nil
    end
    utils.print("done")
    utils.print("checking version")
    t:sendData("v")
    local bootloader_answer = readData(2000)
    utils.print("Bootloader answer: ", bootloader_answer)
    if string.find(bootloader_answer, "Bootloader 1.0") == nil then
        t:close()
        return nil
    end
    return connection
end

local connection = ""
local up_to_date = false
utils.print("Searching for running firmware")
local res = FindFirmware()

if res == nil then
    utils.print("Running firmware not found, searching for bootloaders")
    connection = FindActiveBootloader()
elseif res == "up_to_date" then
    utils.print("Update not needed")
    up_to_date = true
else
    connection = res
end


if up_to_date == true then
    return 0
end

if connection == nil then
    error("No working bootloaders found")
end
utils.print("Bootloader found at ", connection)

utils.print("reading firmware file")

local filename = args["fw_bin_file"]
local file = io.open(filename, "rb")
if file == nil then 
    error("cannot open file "..filename)
end

local firmware_data = file:read("a")
file:close()
utils.print("done")
    
utils.print("preparing")
local final_str = ""
final_str = final_str..serialiseBinaryRPCargument(string.byte("u"), "ui1")
local sz = serialiseBinaryRPCargument(#firmware_data, "ui4")
final_str = final_str..sz:sub(3, 3)..sz:sub(2, 2)..sz:sub(1, 1)
final_str = final_str..firmware_data
final_str = final_str..crc8(firmware_data)
utils.print("done")

local function splitByChunk(text, chunkSize)
    local s = {}
    for i=1, #text, chunkSize do
        s[#s+1] = text:sub(i,i+chunkSize - 1)
    end
    return s
end
utils.print("sending update")

local chunks = splitByChunk(final_str, 127)
prevP = 0
for i,v in ipairs(chunks) do
    if prevP ~= math.floor( i*100/#chunks ) then
        prevP = math.floor( i*100/#chunks )
        utils.print(prevP, "%")
    end
--    delay(3)
t:sendData(v)
end

delay(5000)
t:sendData("v")
local answer = readData(2000)
if answer ~= "Bootloader 1.0" then
    error("Bootloader wrong or no answer: "..answer)
end
delay(1000)
utils.print("resetting back to new FW")
t:sendData("r")
delay(1000)

t:close()
utils.print("waiting until new FW boots")

delay(5000)

utils.print("connecting to new firmware")

local robot = mc.CreateRobot("r",  args["serialnumber"], args["conn"], false, args["serialnumber"] == nil)

local ts = millis()
scheduler.run(function()
    return millis() - ts < 3000 and robot.isConnected == false
end)
if not robot.isConnected then
    error("Cannot connect to updated firmware")
end

utils.print("Ok. Update is complete")
robot:Disconnect()
return 1
