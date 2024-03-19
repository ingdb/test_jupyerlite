import lua_python_binding

def _toLua(arg):
    if type(arg).__name__ == "lua_python_binding_custom":
        return arg
    elif isinstance(arg, (list, tuple)):
        r = lua_python_binding.eval("{}")
        table = lua_python_binding.eval("table")
        for item in arg:
            table.insert(r, _toLua(item))
        return r
    elif isinstance(arg, dict):
        r = lua_python_binding.eval("{}")
        for key in arg:
            r[key] = _toLua(arg[key])
        return r
    else:
        return arg

def _fromLua(arg):
    if isinstance(arg, (list, tuple,)):
        r = []
        for item in arg:
            r.append(_fromLua(item))
        return r
    elif isinstance(arg, dict):
        r = {}
        for key in arg:
            r[key] = _fromLua(arg[key])
        return r
    elif type(arg).__name__ == "lua_python_binding_custom":
        r = dict()
        for key in arg:
            r[key] = _fromLua(arg[key])
        return r
    else:
        return arg