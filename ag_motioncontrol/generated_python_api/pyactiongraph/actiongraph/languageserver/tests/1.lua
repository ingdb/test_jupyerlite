local json = require'json'
local path_lib = require'pl.path'
local utils = require"utils"
local actionGraphSourceCodeParserModule = require'interpreter'.parser
actionGraphSourceCodeParserModule.usecoloredoutput = false
local parser = actionGraphSourceCodeParserModule.SourceCodeParser()
local Linker = require'interpreter'.linker.ProgramLinker
local packagePaths = "/Users/tucher/delta-sticker/actiongraph_packages"

local linker = Linker(
    function(path)
		path = path_lib.abspath(path)
        if parser.modules[path] ~= nil then
            return parser.modules[path]
        end
        parser:addSourceFromYAMLFile(path)
        return parser.modules[path]
    end,
	function() 
        return packagePaths 
    end
)
local path = "/Users/tucher/delta-sticker/more-ls.com/robot_fixed_ag_program/main_3_axes.yaml"
linker:AddModule(path)
local params = {
    position = {
        line = 14,
        character = 15
    }
}

local invlaid = parser:InvalidBlocks()
for _, i in ipairs(invlaid) do
    print("INVALID BLOCK", i)
end
-- linker:MakeByteCodeAndABI()

local modules, lua_scripts = linker:CollectSourceCodeFiles("/Users/tucher/delta-sticker/more-ls.com/robot_fixed_ag_program/main_3_axes.yaml")
print("MODULES:")
for m, _ in pairs(modules) do
    print(m.path)
end

print("SCRIPTS:")
for m, _ in pairs(lua_scripts) do
    print(m)
end
-- 	-- log("hove file path: %s", path)
-- local info, ok = linker:EntitiesByTextCoordinates(path, {line = params.position.line + 1, column = params.position.character + 1})

-- -- utils.recursivePrint(info)

-- local resolvedEntity = info[#info]
-- local thisBlock = resolvedEntity.block
-- local d = thisBlock:getChildValueByClass('DescriptionString')
-- local description = "No description"
-- local header = ""
-- if d then description = d.Content end
-- local isEmbedded = resolvedEntity:isInstance(linker.EmbeddedType)
-- if isEmbedded then
--     description = string.format("Basic type **%s**", thisBlock.Content)
--     if resolvedEntity.EmbeddedTypeSrc.Description then
--         description = description .. "\n\n\n"..resolvedEntity.EmbeddedTypeSrc.Description
--     end
-- end

-- local range
-- for i=#info,1,-1 do
--     if not info[i]:isInstance(linker.EmbeddedType) and 
--         not info[i]:isInstance(linker.ExportedType) and 
--         not info[i]:isInstance(linker.ImportedType) and 
--         info[i].block.SrcMeta.srcPath == path_lib.abspath(path)  then
--         range = {
--             start =   {line = info[i].block.SrcMeta.srcStart.line - 1, character = info[i].block.SrcMeta.srcStart.column - 1},
--             ['end'] = {line = info[i].block.SrcMeta.srcEnd.line - 1,   character = info[i].block.SrcMeta.srcEnd.column - 1}
--         }
--         break
--     end
-- end
-- if resolvedEntity.kind ~= nil then
--     header = string.format( "*%s*\n\n\n",resolvedEntity.kind)
-- end
-- local definedAt = ""
-- if not isEmbedded then
--     local srcPath = thisBlock.SrcMeta.srcPath
--     if path_lib.is_windows then
--         srcPath = "/"..string.gsub(srcPath, "\\", "/")
--     end
--     local vsCodeLink = string.format("file://%s#L%d", srcPath, thisBlock.SrcMeta.srcStart.line)

--     definedAt = string.format("\n\n---\n\nDefined at [%s:%d](%s)", thisBlock.SrcMeta.srcPath, thisBlock.SrcMeta.srcStart.line, vsCodeLink)
-- end
-- local text = string.format("%s%s%s", header, description, definedAt)
-- local data = {
--     contents = {
--         kind = 'markdown',
--         -- kind = 'plaintext',
--         -- value = 'ffuuu'
--         value = text
--     },
--     range = range
-- }