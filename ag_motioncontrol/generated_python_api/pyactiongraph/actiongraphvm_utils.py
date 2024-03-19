from .lua import setup_lua_interpreter
from pprint import pprint as print
setup_lua_interpreter()
import lua_python_binding
from .lua.utils import _fromLua, _toLua
lua_python_binding.require("lua_actiongraphvm_utils")
fifth_order_movement_optimize_time = lua_python_binding.globals().actiongraphvm_utils.fifth_order_movement_optimize_time
_Vector = lua_python_binding.require("vector")

def to_vector(value):
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError(f"{value} cannot be converted to vector")
    return _Vector(*value)

def calculate_movement_time(DriftMax, JMax, AMax, SpeedMax, P0, V0, A0, P1, V1, A1):
    return fifth_order_movement_optimize_time(
        DriftMax, 
        JMax, 
        AMax, 
        SpeedMax, 
        to_vector(P0),
        to_vector(V0),
        to_vector(A0),
        to_vector(P1),
        to_vector(V1),
        to_vector(A1)
    )
