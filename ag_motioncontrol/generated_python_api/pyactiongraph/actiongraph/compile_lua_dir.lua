require"lua_actiongraph_utils"
local lfs = require"lfs"
local path_lib = require("pl.path")
local delete = require("pl.file").delete
local function compilefiles (path)
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." then
            local f = path_lib.join(path, file)
            local attr = lfs.attributes (f)
            if attr == nil then
                print("not attr for ", f)
            elseif attr.mode == "directory" then
                compilefiles (f)
            else
                if path_lib.extension(file) == ".lua" then
                    compile_file_to_bytecode(f, f.."c")
                    delete(f)
                end
            end
        end
    end
end

compilefiles (cmd_args[1])

