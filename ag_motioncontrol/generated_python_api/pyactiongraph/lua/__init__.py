import sys
import platform
from os import path

__setup = False

def add_lua_path(lg, id, path):
        lg.package[id] += ";" + path

def add_lua_search_dir(lg, p):
    pe = path.abspath(p)
    pl = platform.system()
    if pl == "Darwin":
        add_lua_path(lg, "path", pe + "/?/init.lua")
        add_lua_path(lg, "path", pe + "/?/init.luac")
        add_lua_path(lg, "path", pe + "/?.lua")
        add_lua_path(lg, "path", pe + "/?.luac")
        add_lua_path(lg, "cpath",pe + "/?.dylib")
    elif pl == "Windows":
        add_lua_path(lg, "path", pe + "\\?\\init.lua")
        add_lua_path(lg, "path", pe + "\\?\\init.luac")
        add_lua_path(lg, "path", pe + "\\?.lua")
        add_lua_path(lg, "path", pe + "\\?.luac")
        add_lua_path(lg, "cpath",pe + "\\?.dll")
    elif pl == "Linux":
        add_lua_path(lg, "path", pe + "/?/init.lua")
        add_lua_path(lg, "path", pe + "/?/init.luac")
        add_lua_path(lg, "path", pe + "/?.lua")
        add_lua_path(lg, "path", pe + "/?.luac")
        add_lua_path(lg, "cpath",pe + "/?.so")

def setup_lua_interpreter(base_interpreter_search_path=None):
    global __setup
    pl = platform.system()
    script_path = path.dirname(path.abspath(__file__))

    if  __setup:
        return

    if base_interpreter_search_path == None:
        current_path = script_path
    elif not path.isabs(base_interpreter_search_path):
        current_path = path.join(current_path, base_interpreter_search_path)
    

    if pl == "Darwin":
        if platform.machine() != "x86_64" and platform.machine() != "AMD64":
            binpath = path.join(current_path, "lua_interpreter", "macos")
        else:
            binpath = path.join(current_path, "lua_interpreter", "macos_x86")
        sys.path.append(binpath)
        import subprocess
        subprocess.call(f"xattr -d com.apple.quarantine {path.join(binpath, '*')}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.call(f"chmod +x   {path.join(binpath, '*')}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif pl == "Windows":
        sys.path.append(path.join(current_path, "lua_interpreter", "windows"))
        from os import add_dll_directory
        add_dll_directory(path.join(current_path, "lua_interpreter", "windows"))
    elif pl == "Linux":
        import subprocess
        if platform.machine() == "x86_64" or platform.machine() == "AMD64":
            bin_path = path.join(current_path, "lua_interpreter", "linux-x86_64")
            sys.path.append(bin_path)
            subprocess.call(f"chmod +x   {path.join(bin_path, '*')}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            bin_path = path.join(current_path, "lua_interpreter", "linux-aarch64")
            sys.path.append(bin_path)
            subprocess.call(f"chmod +x   {path.join(bin_path, '*')}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    import lua_python_binding # should not throw
    lg = lua_python_binding.globals()

    if pl == "Darwin":
        if platform.machine() != "x86_64" and platform.machine() != "AMD64":
            add_lua_search_dir(lg, path.join(current_path, "lua_interpreter", "macos"))
        else:
            add_lua_search_dir(lg, path.join(current_path, "lua_interpreter", "macos_x86"))
    elif pl == "Windows":
        add_lua_search_dir(lg, path.join(current_path, "lua_interpreter", "windows"))
    elif pl == "Linux":
        if platform.machine() == "x86_64" or platform.machine() == "AMD64":
            add_lua_search_dir(lg, path.join(current_path, "lua_interpreter", "linux-x86_64"))
        else:
            add_lua_search_dir(lg, path.join(current_path, "lua_interpreter", "linux-aarch64"))

    __setup = True
    

def add_lua_search_paths(additonal_lua_paths):
    import lua_python_binding
    lg = lua_python_binding.globals()
    script_path = path.dirname(path.abspath(__file__))
    for p in additonal_lua_paths:
        if not path.isabs(p):
            p = path.join(script_path, p)
        add_lua_search_dir(lg, path.join(p))