local utils = require("utils")
utils.trace_info = true

local transport_conn
if #cmd_args == 1 then
    transport_conn = "serialport2="..cmd_args[1]
end
cmd_args[1] = "fw_bin_file=firmware.bin"
cmd_args[2] = "version_file=version_info.h"
cmd_args[3] = "force=true"
if transport_conn ~= nil then
    cmd_args[4] = "conn="..transport_conn
end
utils.print("Doing forced FW update")
local update_result, update_err = pcall(function () require("firmware_update") end)
if update_result == false then
    error("Update failure: "..update_err)
end

utils.print("Done")
