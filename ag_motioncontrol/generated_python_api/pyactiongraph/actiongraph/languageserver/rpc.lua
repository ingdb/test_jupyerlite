-- json-rpc implementation
local json = require 'json'
local rpc = {}
local function sendToStdout(data)
	io.write(data)
	io.flush()
	-- io.stderr:write(string.format("Written to stdout: %d bytes", string.len( data )))
	-- local requestsDumpFile = io.open("requestsDump.txt", "ab")
	-- requestsDumpFile:write(string.format("\nDATABEGIN\n%s\nDATAEND", data))
	-- requestsDumpFile:close()
end
function rpc.respond(id, result)
	local msg = json.stringify({
		jsonrpc = "2.0",
		id = id or json.null,
		result = result
	})
	sendToStdout("Content-Length: ".. string.len(msg).."\r\n\r\n"..msg)
end

local lsp_error_codes = {
	-- Defined by json-rpc
	ParseError           = -32700,
	InvalidRequest       = -32600,
	MethodNotFound       = -32601,
	InvalidParams        = -32602,
	InternalError        = -32603,
	serverErrorStart     = -32099,
	serverErrorEnd       = -32000,
	ServerNotInitialized = -32002,
	UnknownErrorCode     = -32001,
	-- Defined by the protocol.
	RequestCancelled     = -32800,
}

local valid_content_type = {
	["application/vscode-jsonrpc; charset=utf-8"] = true,
	-- the spec says to be lenient in this case
	["application/vscode-jsonrpc; charset=utf8"] = true
}

function rpc.respondError(id, errorMsg, errorKey, data)
	if not errorMsg then
		errorMsg = "missing error message!"
	end
	local msg = json.stringify({
		jsonrpc = "2.0",
		id = id or json.null,
		error = {
			code = lsp_error_codes[errorKey] or -32001,
			message = errorMsg,
			data = data
		}
	})
	sendToStdout("Content-Length: ".. string.len(msg).."\r\n\r\n"..msg)
	io.stderr:write("Error: "..errorMsg.."\n")
	io.stderr:flush()
end

function rpc.notify(method, params)
	local msg = json.stringify({
		jsonrpc = "2.0",
		method = method,
		params = params
	})
	sendToStdout("Content-Length: ".. string.len(msg).."\r\n\r\n"..msg)
end

local open_rpc = {}
local next_rpc_id = 0
function rpc.request(method, params, fn)
	local msg = json.stringify({
		jsonrpc = "2.0",
		id = next_rpc_id,
		method = method,
		params = params
	})
	open_rpc[next_rpc_id] = fn
	next_rpc_id = next_rpc_id + 1
	sendToStdout("Content-Length: ".. string.len(msg).."\r\n\r\n"..msg)
end

function rpc.finish(data)
	-- response to server request
	local call = open_rpc[data.id]
	if call then
		call(data.result)
	end
end

function rpc.decode()
	local line = io.read("*l")
	if line == nil then
		return nil, "eof"
	end
	line = line:gsub("\13", "")
	local content_length
	while line ~= "" do
		local key, val = line:match("^([^:]+): (.+)$")
		assert(key, string.format("%q", tostring(line)))
		assert(val)
		if key == "Content-Length" then
			content_length = tonumber(val)
		elseif key == "Content-Type" then
			assert(valid_content_type[val], "Invalid Content-Type")
		else
			error("unexpected http key")
		end
		line = io.read("*l")
		line = line:gsub("\13", "")
	end

	-- body
	assert(content_length, "no content length in message")
	local data = io.read(content_length)
	data = data:gsub("\13", "")
	data = assert(json.parse(data), "malformed json")
	assert(data["jsonrpc"] == "2.0", "incorrect json-rpc version")
	return data
end

return rpc