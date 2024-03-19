local rpc = require'rpc'
local log = require'log'
local json = require'json'
local path_lib = require'pl.path'

local actionGraphSourceCodeParserModule = require'interpreter'.parser
actionGraphSourceCodeParserModule.usecoloredoutput = false
local parser = actionGraphSourceCodeParserModule.SourceCodeParser()
local Linker = require'interpreter'.linker.ProgramLinker
local packagePaths = ""

local linker = Linker(
    function(path)
		path = path_lib.abspath(path)
        if parser.modules[path] ~= nil then
            return parser.modules[path]
        end
        log("Auto loading file to parser: %s", path)
        parser:addSourceFromYAMLFile(path)
        return parser.modules[path]
    end,
	function() return packagePaths end
)
parser:subscribe(function(path, event)
    -- log("NOTIFICATION FIRED for %s: %s", path, event)
	
	linker:RebuildDependenciesForPath(path)
end)

local function decodeChar(hex)
	return string.char(tonumber(hex,16))
end
 
local function decodeString(str)
	local output, t = string.gsub(str,"%%(%x%x)",decodeChar)
	return output
end

local function URIToAbsPath(uri)
	local decoded = decodeString(uri)
	local ret = decoded:gsub("^[^:]+://", "")
	if ret:sub(1, 1) == '/' and ret:find(':') then
		ret = ret:sub(2, -1)
	end
	-- log("Before '%s', after '%s'", uri, ret)
	return ret
end


local method_handlers = {}



local function printParams(params)
	for k, v in pairs(params) do
		log(string.format("\tkey: %s\t value: %s\n", k, v))
	end
end

function method_handlers.initialize(params, id)
	if Initialized then
		error("already initialized!")
	end
	-- log(string.format("params.rootPath: %s\n",params.rootPath))
	-- log(string.format("params.rootUri: %s\n",params.rootUri))

	-- local f       = assert(io.open(uri:gsub("^[^:]+://", ""), "r"))
		-- document.text = f:read("*a")

	-- printParams(params)

	-- Config.root  = params.rootPath or params.rootUri
	-- log.setTraceLevel(params.trace or "off")
	-- log.info("Config.root = %q", Config.root)
	-- analyze.load_completerc(Config.root)
	-- analyze.load_luacheckrc(Config.root)
	--ClientCapabilities = params.capabilities
	if params.initializationOptions and params.initializationOptions.ActionGraphPackagePath then
		packagePaths = params.initializationOptions.ActionGraphPackagePath
		log("Init value for packagePaths: %s", packagePaths)
	end
	Initialized = true

	-- hopefully this is modest enough
	return rpc.respond(id, {
		capabilities = {
			completionProvider = {
				triggerCharacters = {".",":"},
				resolveProvider = false
			},
			definitionProvider = true,
			textDocumentSync = {
				openClose = true,
				change = 1, -- 1 is non-incremental, 2 is incremental
				save = { includeText = true },
			},
			hoverProvider = { workDoneProgress = true },
			-- documentSymbolProvider = true,
			--referencesProvider = false,
			--documentHighlightProvider = false,
			--workspaceSymbolProvider = false,
			codeActionProvider = true,
			--documentFormattingProvider = false,
			--documentRangeFormattingProvider = false,
			--renameProvider = false,
		}
	})
end

function method_handlers.initialized(params, id)
	-- log(string.format("initialized called\n"))
	-- printParams(params)

	rpc.request("workspace/configuration", {
		items = {{
			section = "actiongraph"
		}}
	}, function(result)
		if result and result[1] and result[1].ActionGraphPackagePath then
			packagePaths = result[1].ActionGraphPackagePath
			log("Package path adjusted: ".. packagePaths)
		end
	end
	)
end

local function clearDiagnosticsForDocument(uri)
	rpc.notify("textDocument/publishDiagnostics", {
		uri = uri,
		diagnostics = json.empty_array
	})
end
local function sendDiagnosticsForDocument(uri)
	local path = URIToAbsPath(uri)
	local diagnostic = {
		uri = uri,
		diagnostics = {}
	}
	local testDiagnosticEntry = {
		range = {start = {line = 0, character = 0}, ['end'] = {line = 3, character = 0}},
		severity = 2, -- 1 error 2 warning 3 hint 4 hint
		code = "<diagnostic code>",
		codeDescription = {href = "https://fu.com"},
		source = "actiongraph",
		message = "Hello, I am first diagnostic message!",
		tags = {1}, -- 1 Unnecessary 2 Deprecated
		data = {someField = {another_field = {value = true}}}, -- A data entry field that is preserved between a * `textDocument/publishDiagnostics` notification and * `textDocument/codeAction` request.
		relatedInformation = {
			{
				location = {
					uri = uri,
					range = {start = {line = 10, character = 0}, ['end'] = {line = 12, character = 0}}
				},
				message = "I am related information"
			},
		}
	}
	table.insert( diagnostic.diagnostics,  testDiagnosticEntry)
	-- rpc.notify("textDocument/publishDiagnostics", diagnostic)
end

method_handlers["textDocument/didOpen"] = function(params)
	-- log("textDocument/didOpen: %s", params.textDocument.uri)
	local path = 	URIToAbsPath(params.textDocument.uri)
	parser:addSourceFromYAMLFile(path, params.textDocument.text)
	
	
	linker:AddModule(path)


	log("Document added: %s", path)
	sendDiagnosticsForDocument(params.textDocument.uri)
end

method_handlers["textDocument/didClose"] = function(params)
	local path = 	URIToAbsPath(params.textDocument.uri)
	parser:removeSourceByPath(path)
	
	linker:RemoveModule(path)
	
	log("Document closed: ".. path..'\n')
	clearDiagnosticsForDocument(params.textDocument.uri)
end

method_handlers["textDocument/didChange"] = function(params)
	local path = 	URIToAbsPath(params.textDocument.uri)
	parser:addSourceFromYAMLFile(path, params.contentChanges[1].text)
	log("Document updated: ".. path..'\n')
	sendDiagnosticsForDocument(params.textDocument.uri)
end

method_handlers["textDocument/didSave"] = function(params)
	local path = 	URIToAbsPath(params.textDocument.uri)
	log("Document saved: ".. path..'\n')
end

method_handlers["textDocument/hover"] = function(params, id)
	local path = 	URIToAbsPath(params.textDocument.uri)
	-- log("hove file path: %s", path)
	local info, ok = linker:EntitiesByTextCoordinates(path, {line = params.position.line + 1, column = params.position.character + 1})


	if not info or not ok then -- broken module
		log("No linker info for given coords")
		local info = parser:BlocksByTextCoordinates(path, {line = params.position.line + 1, column = params.position.character + 1})
		if info == nil or #info == 0 then 
			return rpc.respond(id, json.null)
		end
	
		local thisBlock = info[1]
		return rpc.respond(id, {
			contents = {
				kind = 'plaintext',
				value = tostring(thisBlock),
			},

			range = {
				start =   {line = thisBlock.SrcMeta.srcStart.line - 1, character = thisBlock.SrcMeta.srcStart.column - 1},
				['end'] = {line = thisBlock.SrcMeta.srcEnd.line - 1,   character = thisBlock.SrcMeta.srcEnd.column - 1}
			}
		})
	end
	-- local info = parser:BlocksByTextCoordinates(path, {line = params.position.line + 1, column = params.position.character + 1})
	if info == nil or #info == 0 then 
		return rpc.respond(id, json.null)
	end

	local resolvedEntity = info[#info]
	local thisBlock = resolvedEntity.block
	local d = thisBlock:getChildValueByClass('DescriptionString')
	local description = "No description"
	local header = ""
	if d then description = d.Content end
	local isEmbedded = resolvedEntity:isInstance(linker.EmbeddedType)
	if isEmbedded then
		description = string.format("Basic type **%s**", thisBlock.Content)
		if resolvedEntity.EmbeddedTypeSrc.Description then
			description = description .. "\n\n\n"..resolvedEntity.EmbeddedTypeSrc.Description
		end
	end

	local range
	for i=#info,1,-1 do
		if not info[i]:isInstance(linker.EmbeddedType) and 
		   not info[i]:isInstance(linker.ExportedType) and 
		   not info[i]:isInstance(linker.ImportedType) and 
		   info[i].block.SrcMeta.srcPath == path_lib.abspath(path)  then
			range = {
				start =   {line = info[i].block.SrcMeta.srcStart.line - 1, character = info[i].block.SrcMeta.srcStart.column - 1},
				['end'] = {line = info[i].block.SrcMeta.srcEnd.line - 1,   character = info[i].block.SrcMeta.srcEnd.column - 1}
			}
			break
		end
	end
	if resolvedEntity.kind ~= nil then
		header = string.format( "*%s*\n\n\n",resolvedEntity.kind)
	end
	local definedAt = ""
	if not isEmbedded then
		local srcPath = thisBlock.SrcMeta.srcPath
		if path_lib.is_windows then
			srcPath = "/"..string.gsub(srcPath, "\\", "/")
		end
		local vsCodeLink = string.format("file://%s#L%d", srcPath, thisBlock.SrcMeta.srcStart.line)

		definedAt = string.format("\n\n---\n\nDefined at [%s:%d](%s)", thisBlock.SrcMeta.srcPath, thisBlock.SrcMeta.srcStart.line, vsCodeLink)
	end
	local text = string.format("%s%s%s", header, description, definedAt)
	local data = {
		contents = {
			kind = 'markdown',
			-- kind = 'plaintext',
			-- value = 'ffuuu'
			value = text
		},
		range = range
	}
	return rpc.respond(id, data)
end

method_handlers["textDocument/definition"] = function(params, id)
	log(string.format("textDocument/definition called\n"))
	-- printParams(params)
	return rpc.respond(id, json.null)
end


method_handlers["codeAction/resolve"] = function(params, id) 
	log(string.format("codeAction/resolve called\n"))
end


method_handlers["textDocument/codeAction"] = function(params, id)
	-- log(string.format("textDocument/codeAction called\n"))
	-- printParams(params)
	return rpc.respond(id,  json.empty_array)
	-- return rpc.respond(id, {
	-- 	{
	-- 		title = "Fix alias(examle)",
	-- 		kind = 'quickfix',
	-- 		diagnostics = params.context.diagnostics,
	-- 		isPreferred = true,
	-- 		-- disabled = {reason = "what is this?"},
	-- 		-- edit = { https://microsoft.github.io/language-server-protocol/specifications/specification-3-17/#workspaceEdit

	-- 		-- },
	-- 		-- command = {

	-- 		-- },
	-- 		-- data = {someField = {another_field = {value = true}}}
	-- 	}
	-- })
end

method_handlers["textDocument/completion"] = function(params, id)
	return rpc.respond(id,  json.null)
	-- return rpc.respond(id, {
	-- 	isIncomplete = false,
	-- 	items = {
	-- 		{
	-- 			label = "A"
	-- 		},
	-- 		{
	-- 			label = "B"
	-- 		}
	-- 	}
	-- })
end

function method_handlers.shutdown(params, id)
	os.exit(0)
end

method_handlers["workspace/didChangeConfiguration"] = function(params)
	log("HERE")
	assert(params.settings)
	-- merge_(Config, params.settings)
	log("Config loaded, new config: ", require'json'.stringify(params.settings))
end

return method_handlers
