local P = {}   -- package


local path_lib = require("pl.path")
local utils = require("utils")
local table = table
local ipairs = ipairs
local dir_lib = require("pl.dir")
local pairs = pairs
local error = error
local ag_utils = require'interpreter.helpers'
local NewModuleContext = require'interpreter.module_context'.NewModuleContext

local log = ag_utils.log
local readSrc  = ag_utils.readSrc
local globalEnv = _ENV
local _ENV = P
PACKAGE_PATHS = globalEnv.ACTIONGRAPH_PACKAGE_SEARCH_PATH
if PACKAGE_PATHS ~= nil then
    utils.info(5, "PACKAGE PATH: ", PACKAGE_PATHS)
end
SRC_EXENSION = ".yaml"

local function findPkgDir(package_name, base_dir, PACKAGE_PATHS)
    local name = path_lib.basename(package_name)

    local dirsToSearch = {".", base_dir, PACKAGE_PATHS}
    for _, pkgPath in ipairs(dirsToSearch) do
        if path_lib.exists(pkgPath) and path_lib.isdir(pkgPath) then

            for _, dirName in ipairs(dir_lib.getdirectories(pkgPath)) do
                if name == path_lib.basename(dirName) then
                    local initFilePath = path_lib.join(dirName, "__index__.yaml")
                    if path_lib.exists(initFilePath) and path_lib.isfile(initFilePath) then
                        return path_lib.abspath(dirName)
                    end
                end
            end
        end
    end
    error("Package '" ..package_name .."' not found")
end

function NewPackageContext(package_name, base_dir, PACKAGE_PATHS)
    local ext = path_lib.extension(package_name)
    local fullName = path_lib.abspath(package_name, base_dir)
    if ext == SRC_EXENSION and path_lib.isfile(fullName) then
        return NewModuleContext(package_name, base_dir, PACKAGE_PATHS)
    end

    local pkg_dir = utils.checkError(function() return findPkgDir(package_name, base_dir, PACKAGE_PATHS) end)
    -- log("Exploring package", pkg_dir)
    local raw_structure = readSrc(path_lib.join(pkg_dir, "__index__.yaml"))

    if raw_structure.Export == nil then error("no exported entities") end
    local ret = {
        path = pkg_dir,
        index = raw_structure.Export,
        loaded_modules = {}
    }

    function ret:resolveType(entityType, typeName)
        if self.index[entityType] == nil then return nil end
        for module_name, exportList in pairs(self.index[entityType]) do
            for _, exportedHWId in ipairs(exportList) do
                if exportedHWId == typeName then
                    if self.loaded_modules[module_name] == nil then
                        self.loaded_modules[module_name] = NewModuleContext(path_lib.join(self.path, module_name..SRC_EXENSION), self.path, PACKAGE_PATHS)
                    end
                    return self.loaded_modules[module_name]:resolveType(entityType, typeName)
                end
            end
        end
    end

    return ret
end

return P
