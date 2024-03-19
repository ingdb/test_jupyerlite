require"lua_actiongraph_utils"
require"custom_lowlevel_functions"
local utils = {
   print_to_file=false,
   trace_info=true,
   info_level = 0
}

function utils.tohex(str)
  return (str:gsub('.', function (c)
      return string.format('%02X', string.byte(c))
  end))
end

function utils.printDeg(v)
    return string.format("% 3.1f",  math.deg(v)) .. "°"
end

function utils.printF(v)
    return string.format("% 2.3f",  v)
end

local function fsize (file)
  local current = file:seek()      -- get current position
  local size = file:seek("end")    -- get file size
  file:seek("set", current)        -- restore position
  return size
end
 
function utils.writeToLogFile(v, name)
    local fname = name or "runtime.log"
	-- Opens a file in append mode
	local file = io.open(fname, "a")

	-- appends a word test to the last line of the file
	file:write(v)
	file:write("\n")

	-- closes the open file
	file:close()
end

function utils.date_string()
	local seconds, millis  = math.modf(unix_time()) 
  return os.date("%Y/%m/%d %H:%M:%S", seconds) .. "." .. string.format("%03.f",  millis * 1000)
end

function utils.printFunction(data)
    io.stderr:write(data)
    io.stderr:flush()
end
function utils.recursivePrint(tb, level, endl_needed, tables_visited)
    if not level then level = 0 end
    if  endl_needed == nil then endl_needed = true end
    if tables_visited == nil then
        tables_visited = {}
    end
    local indent = ""
    for i=0,level do indent = indent .. "  " end
    if type(tb) ~= "table" then
        utils.printFunction(indent..tostring(tb))
        if endl_needed == true then
            utils.printFunction("\n")
        end
        return
    end
    if tables_visited[tb] == true then
        utils.printFunction(indent.."ALREADY PRINTED BEFORE")
        if endl_needed == true then
            utils.printFunction("\n")
        end
        return
    end
    tables_visited[tb] = true
    
    utils.printFunction(indent.."{\n")
    for k, v in pairs(tb) do
        utils.recursivePrint(k, level + 1, false, tables_visited)
        utils.printFunction(":\n")
        utils.recursivePrint(v, level + 2, true, tables_visited)
    end
    utils.printFunction(indent.."}\n")
end


function utils.print(...)
    local arg = {...}
    local printResult = ""
    for i,v in ipairs(arg) do
        printResult = printResult .. tostring(v) .. "\t"
    end

    local message = ""
	  

    if utils.trace_info then
      local info = debug.getinfo(2)
      local filename = info.source:match("[^/\\]*.lua$") or info.short_src
      local line = info.currentline
      message = "[" .. utils.date_string()
                .. " " .. tostring(filename) .. ":" .. tostring(line) .. "] " .. printResult
    else 
      message = printResult
    end
	
	-- write to console
    utils.printFunction(message.."\n")
	if utils.print_to_file then
		utils.writeToLogFile(message)
	end
end

function utils.info(level, ...)
    if utils.info_level < level then
        return
    end
    local arg = {...}
    local printResult = ""
    for i,v in ipairs(arg) do
        printResult = printResult .. tostring(v) .. "\t"
    end

    local message = ""
	  

    if utils.trace_info then
      local info = debug.getinfo(2)
      local filename = info.source:match("[^/\\]*.lua$") or info.short_src
      local line = info.currentline
      message = "[" .. utils.date_string()
                .. " " .. tostring(filename) .. ":" .. tostring(line) .. "] " .. printResult
    else 
      message = printResult
    end
	
	-- write to console
    utils.printFunction(message.."\n")
	
end
function utils.error(...)
  local arg = {...}
  local printResult = ""
  for i,v in ipairs(arg) do
      printResult = printResult .. tostring(v) .. "\t"
  end

  local message = ""
  if utils.trace_info then

    local info = debug.getinfo(2)
    local filename = info.source:match("[^/\\]*.lua$") or info.short_src
    local line = info.currentline
    message = "[" .. utils.date_string()
              .. " " .. tostring(filename) .. ":" .. tostring(line) .. "] " .. printResult
  else 
    message = printResult
  end
  if utils.print_to_file then
    utils.writeToLogFile(message)
  end
-- write to console
  error(message)

 
end

function utils.logError(...)
  local arg = {...}
  local printResult = ""
  for i,v in ipairs(arg) do
      printResult = printResult .. tostring(v) .. "\t"
  end

  local info = debug.getinfo(2)
  local filename = info.short_src
    local line = info.currentline

    local message = "[" .. utils.date_string()
              .. ":" .. tostring(filename) .. ":" .. tostring(line) .. "] " .. printResult
  
    utils.writeToLogFile(message, "runtime_errors.txt")
end

function utils.tableclone(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function utils.parseJSONFile(path)
  local file = io.open(path, 'r')
  if file == nil then return nil end
  local data = file:read("a")
  file:close()
  local res, parse_res = pcall(function()return require'json'.parse(data)end)
  if res == true then 
    return parse_res  
  else 
    utils.print("JSON parsing error:", parse_res)
    return nil
  end

end

function utils.parseYAMLFile(path)
  local file = io.open(path, 'r')
  if file == nil then return nil end

  local data = file:read("a")
  file:close()
  local res, parse_res = pcall(function()
    return require"lyaml".load(data, {add_metainfo=true})
  end)
  if res == true then 
    return parse_res  
  else 
    utils.print("YAML parsing error:", parse_res)
    return nil
  end
end

function utils.createFileContentChangesWatcher(path, callback, period)
  local ret = {
    path = path,
    callback = callback,
    last_hash = "",
    period = period or 500,
    last_check_ms = nil
  }
  ret.tick = function()
    if ret.last_check_ms ~= nil and millis() - ret.last_check_ms < ret.period then
      return
    end
    ret.last_check_ms = millis()
    local file = io.open(path, 'r')
    if file == nil then 
      return 
    end
    local data = file:read("a")
    file:close()
    local currentHash = memory64bitHash(data)
    if currentHash~= ret.last_hash then

      local res, clb_res = pcall(function()
				return ret.callback(data)
			end)
      if res == true and clb_res == nil then
        ret.last_hash = currentHash
      end
    end
  end
  ret.tick()
  return ret
end



function utils.checkError(clb)
  local ok, result = pcall(clb)
  if ok == false then
    local errTxt = tostring(result).."\n"
    for i=2,20 do
        local info = debug.getinfo(i)
        if info == nil then break end

        local n = info.name or "n/a"
        local src = info.source or "n/a"
        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
        local line = info.currentline or "n/a"
        errTxt = errTxt .. "\t" .. src .. "," .. line .. ": " .. n .. "\n"
    end
  
    error("[" .. utils.date_string()
						  .. "] "..errTxt)
  end
  return result
end

function utils.getDbgStackTrace()
    local errTxt = ""
    for i=2,20 do
        local info = debug.getinfo(i)
        if info == nil then break end

        local n = info.name or "n/a"
        local src = info.source or "n/a"
        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
        local line = info.currentline or "n/a"
        errTxt = errTxt .. "\t" .. src .. "," .. line .. ": " .. n .. "\n"  
  end
  return errTxt
end
function utils.errorExt(...)

  local errTxt = ""
  for _, a in ipairs({...}) do
    errTxt = errTxt .. tostring(a).." "
  end
  errTxt = errTxt.."\n"
  for i=2,20 do
        local info = debug.getinfo(i)
        if info == nil then break end

        local n = info.name or "n/a"
        local src = info.source or "n/a"
        if src:sub(1,1) ~= "@" and src ~= "n/a" then src = "<script>" end
        local line = info.currentline or "n/a"
        errTxt = errTxt .. "\t" .. src .. "," .. line .. ": " .. n .. "\n"
  
    
  end
  error("[" .. utils.date_string()
						  .. "] "..errTxt, 2)
end

function utils.defer(f, ...)
    local args = {...}
    return setmetatable({}, {
        __close = function()
            f(table.unpack(args))
        end
    })
end
return utils
