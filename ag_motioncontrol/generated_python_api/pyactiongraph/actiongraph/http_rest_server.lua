local http_rest_server = {}
local json = require'json'
local scheduler = require'scheduler'
local socket = require 'socket'
local Handler = require 'pegasus.handler'
local utils = require("utils")




local function url_matcher(pattern, path)
    local names = {}
    local p = string.gsub(pattern, "({%a+})", function (val)
        table.insert(names, string.sub(val, 2, -2))
        return "(%w+)"
    end)

    local parsed = {}
    local vals = {string.match(path, p)}
    if vals[1] == nil then
        return false, parsed
    end
    if vals[1] == path then
        return true, parsed
    end
    for k, v in pairs(vals) do
        parsed[names[k]] = v
    end


    return true, parsed
end

local server = {}
function server:h(method, path, f)
    self.handlers[method][path] = f
end

function server:dumpRequest (table, hide_prefix)
	local output = ""
    local path = table['_path']
    
    if hide_prefix then
        path = path:gsub(self.prefix, "..")
    end
	output = output .. "Method: [" .. table['_method'] .. "] ";
	output = output .. "Path: [" .. path .. "] ";
	output = output .. "Query: [" .. table['_query_string'].. "] ";

	return output;
end

function server:json_h(path, f)
    self:h("POST", path, function(r, w)
        local headers = r:headers()
        local method = r:method()

        if method == "POST" then
            local length = tonumber(headers['Content-Length'])
            if length > 0 then
                local data = r:receiveBody()
                local parse_res, param_dict = pcall(function() return json.parse(data) end)
                if parse_res == false then 
                    return 400, {error=param_dict}
                else
                    return f(param_dict)
                end
            else
                return 400, {}
            end
        else
            return 400, {}
        end
    end
    )
end

function server:main_handler(request, response)
    if false and response.status == 200 then
        -- this has already been responded. don't override response
        if http_rest_server.requests_debug == true then
            utils.print("!-> " .. dumpRequest(request, http_rest_server.requests_debug_hide_prefix))
        end
		return
	end
  
    response:contentType("application/json")
    response:addHeader('Access-Control-Allow-Origin', '*')
    
    if request:method() == "OPTIONS" then
        response:addHeader('Access-Control-Allow-Origin', '*')
        response:addHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
        response:addHeader('Access-Control-Allow-Headers', 'Content-Type')

        response:statusCode(204, "ok"):write()
        return
    end
	if http_rest_server.requests_debug == true then
        utils.print("--> " .. dumpRequest(request, http_rest_server.requests_debug_hide_prefix))
    end
	
    if self.prefix ~= "" then
        local prefix_pos = string.find(request:path(), self.prefix)
        if not prefix_pos or prefix_pos ~= 1 then
			utils.print("<-- 404 No registered handlers for given path. Check API prefix")
            response:statusCode(404, "No registered handlers for given path. Check API prefix"):write()
            return
        end
        request.path_without_prefix = request:path():sub(self.prefix:len() + 1)
    else
        request.path_without_prefix = request:path()
    end

    
    for path, handler in pairs(self.handlers[request:method()]) do
        local matched, params = url_matcher(path, request.path_without_prefix)
        if matched then
            request.path_params = params
            local exec_status, result = pcall(function ()
                return {handler(request, response)}
            end)

            if not exec_status then
				utils.print("<-- 500 " .. tostring(result))
                response:statusCode(500, tostring(result)):write()
            else
                if result == nil then result = {} end
                if result[2] == nil then result[2] = {} end
                if result[1] == nil then result[1] = 200 end
				if http_rest_server.requests_debug == true then
                    utils.print("<-- " .. result[1] .. " " .. json.stringify(result[2]))
                end
                response:statusCode(result[1]):write(json.stringify(result[2]))
            end
            return
        end
    end
	
	utils.print("<-- 404 No registered handlers for given path")
    response:statusCode(404, "No registered handlers for given path"):write()
end


local function create_async_socket(tcp)
    tcp:settimeout(0)
    -- metatable for wrap produces new methods on demand for those that we
    -- don't override explicitly.
    local metat = { __index = function(table, key)
        table[key] = function(...)
            return tcp[key](tcp,select(2,...))
        end
        return table[key]
    end}
    -- create a wrap object that will behave just like a real socket object
    local wrap = {  }
    function wrap:settimeout(value, mode)
        return 1
    end

    function wrap:send(data, first, last)
        first = (first or 1) - 1
        local result, error
        while true do
            result, error, first = tcp:send(data, first+1, last)
            if error ~= "timeout" then 
                return result, error, first
            else
                scheduler.sleep(0)
            end
        end
    end
 
    function wrap:receive(pattern, partial)
        local error = "timeout"
        local value
        while true do
            value, error, partial = tcp:receive(pattern, partial)
            if (error ~= "timeout") then
                return value, error, partial
            else
                scheduler.sleep(0)
            end
        end
    end
  
    return setmetatable(wrap, metat)
end

function http_rest_server.new(opts)
    local s = setmetatable({handlers={GET = {}, POST = {}, OPTIONS = {}}, prefix = opts.prefix or ""}, {__index = server})
    local handler = Handler:new(function(...)s:main_handler(...)end, opts.static_content_path, {})

    scheduler.addTask(function()
        local server = assert(socket.bind(opts.host or '*', opts.port))
        server:settimeout(0)

        while true do
            local client, errmsg = server:accept()

            if client then
                scheduler.addTask(function()
                    handler:processRequest(create_async_socket(client))
                    client:close()
                end)
            end
            scheduler.sleep(0)
        end
    end)
      

    return s
end


return http_rest_server
