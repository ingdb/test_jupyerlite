io.stderr:write("Starting ActionGraph language server\n\n")
local rpc = require("rpc")
local method_handlers = require 'method_handlers'
local log = require 'log'

log.setTraceLevel("messages")

while true do
	local data, err =  rpc.decode()

	if data == nil then
		if err == "eof" then
            return os.exit(1)
        else
		    error(err)
            return
        end
	end
    if data.method then
		-- request
		if not method_handlers[data.method] then
			log.verbose("confused by %t", data)
			err = string.format("%q: Not found/NYI", tostring(data.method))
			if data.id then
				rpc.respondError(data.id, err, "MethodNotFound")
			else
				log.warning("%s", err)
			end
		else
			local ok
			ok, err = xpcall(function()
				method_handlers[data.method](data.params, data.id)
			end, debug.traceback)
			if not ok then
				if data.id then
					rpc.respondError(data.id, err, "InternalError")
				else
					log.warning("%s", tostring(err))
				end
			end
		end
	elseif data.result then
		rpc.finish(data)
	elseif data.error then
		log("client error:%s", data.error.message)
	end

end