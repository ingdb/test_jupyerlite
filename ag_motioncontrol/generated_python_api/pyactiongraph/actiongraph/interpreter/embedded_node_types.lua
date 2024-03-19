local P = {}   -- package



local OrderedTable = require"orderedtable"

local globalEnv = _ENV
local _ENV = P

DELAY = function()
  local params = OrderedTable()
  params.delay = {Type = "Float"}

  return   { Parameters = params , Embedded = true, Description = "Waits until given time interval elapses" }
end

PARAM_ASSIGNER = function()
  local params = OrderedTable()
  params.param_from = {Type = "ANY_LOWLEVEL"}
  params.param_to =  {Type = "ANY_LOWLEVEL", Mutable = true}

  return   { Parameters = params , Embedded = true, Description = "Assignes one parameter to another one" }
end

MOVABLE_STATUS_SAVER = function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.px =  {Type = "Float", Mutable = true}
  params.py =  {Type = "Float", Mutable = true}
  params.pz =  {Type = "Float", Mutable = true}
  params.vx =  {Type = "Float", Mutable = true}
  params.vy =  {Type = "Float", Mutable = true}
  params.vz =  {Type = "Float", Mutable = true}

  params.p =  {Type = "Vector", Mutable = true}
  params.v =  {Type = "Vector", Mutable = true}

  return   { Parameters = params , Embedded = true, OptionalParams = {"px", "py", "pz", "vx", "vy", "vz", "p", "v"},
      Description = "Saves current Movables position/speed to given params"  }
end

DIGITAL_SIGNAL_VALUE_SAVER = function()
  local params = OrderedTable()
  params.signal = {Type = "Integer"}
  params.param =  {Type = "Integer", Mutable = true}

  return   { Parameters = params , Embedded = true, Description = "Stores current Digital Signal value to given param"}
end

ANALOG_SIGNAL_VALUE_SAVER = function()
  local params = OrderedTable()
  params.signal = {Type = "Integer"}
  params.param =  {Type = "Integer", Mutable = true}

  return   { Parameters = params , Embedded = true, Description = "Stores current Analog Signal value to given param" }
end

PC_MSG_WAITER = function()
  local params = OrderedTable()
  params.event = {Type = "PC_EVENT_ID"}

  return   { Parameters = params , Embedded = true, IsPCEventWaiter = true, Description = "Waits until given event comes from host"  }
end

PC_MSG_EMITTER = function()
  local params = OrderedTable()
  params.event = {Type = "PC_EVENT_ID"}

  return   { Parameters = params , Embedded = true, IsPCEventEmitter = true, Description = "Sends event to host"  }
end

DIGITAL_SIGNAL_VALUE_WAITER = function()
  local params = OrderedTable()
  params.signal = {Type = "Integer"}
  params.value =  {Type = "Integer"}

  return   { Parameters = params , Embedded = true, Description = "Waits until given Digital signal goes to given value, then finishes"  }
end

-- MOVEMENT = function()
--   local params = OrderedTable()
--   "", "", "", "", "", "T"
--   params.movable = {Type = "Integer"}
--   params.is_relative =  {Type = "Integer"}
--   params.px =  {Type = "Float"}
--   params.py =  {Type = "Float"}
--   params.pz =  {Type = "Float"}
--   params.vx =  {Type = "Float"}
--   params.vy =  {Type = "Float"}
--   params.vz =  {Type = "Float"}
--   params.accel_limit =  {Type = "Float"}
--   params.drift_limit =  {Type = "Float"}
--   params.speed_limit =  {Type = "Float"}
--   params.max_dynamic_error =  {Type = "Float"}
--   params.max_endpoint_error =  {Type = "Float"}
--   params.T =  {Type = "Float"}

--   params.p = {Type = "Vector"}
--   params.v = {Type = "Vector"}

--   return   { Parameters = params , Embedded = true, OptionalParams = {"px", "py", "pz", "vx", "vy", "vz", "max_dynamic_error", "max_endpoint_error", "T", "p", "v"}, 
--             Description = ""  }
-- end

CALIBRATER = function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.px =  {Type = "Float"}
  params.py =  {Type = "Float"}
  params.pz =  {Type = "Float"}
  params.p =  {Type = "Vector"}

  return   { Parameters = params , Embedded = true, OptionalParams = {"px", "py", "pz", "p"}
  , Description = "Calibrates given movable: given pos becomes Movable's current pos"  }
end

MOVABLE_STATUS_REPORTER = function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.event =  {Type = "PC_EVENT_ID"}
  params.ignore_movable_errors =  {Type = "Integer"}
  params.report_native_coord =  {Type = "Integer"}

  return   { Parameters = params , Embedded = true, OptionalParams = {"ignore_movable_errors", "report_native_coord"} , IsPCEventEmitter = true 
  , Description = "Sends event to host with info about current Movable position" }
end

DURATION_REPORTER = function()
  local params = OrderedTable()
  params.event = {Type = "PC_EVENT_ID"}

  return   { Parameters = params , Embedded = true, IsPCEventEmitter = true  , Description = "Sends event to host with precise time interval between start and stop" }
end

DIGITAL_SIGNAL_VALUE_SETTER = function()
  local params = OrderedTable()
  params.signal = {Type = "Integer"}
  params.value =  {Type = "Integer"}

  return   { Parameters = params , Embedded = true, Description = "Sets current output Digital signal value"  }
end

ANALOG_SIGNAL_VALUE_SETTER = function()
  local params = OrderedTable()
  params.signal = {Type = "Integer"}
  params.value =  {Type = "Float"}

  return   { Parameters = params , Embedded = true, Description = "Sets current output Analog signal value"  }
end

SYNCER = function()
  local params = OrderedTable()

  return   { Parameters = params , Embedded = true, Description = "Does nothing itself, runs until stopped manually. Could be used for syncronisation purposes"  }
end

ANALOG_SIGNAL_VALUE_REPORTER = function()
  local params = OrderedTable()
  params.signal = {Type = "Integer"}
  params.event =  {Type = "PC_EVENT_ID"}

  return   { Parameters = params , Embedded = true, IsPCEventEmitter = true, Description = "Sends current value of given Analog Signal Hardware module to host"  }
end

DIGITAL_SIGNAL_VALUE_REPORTER = function()
  local params = OrderedTable()
  params.signal = {Type = "Integer"}
  params.event =  {Type = "PC_EVENT_ID"}

  return   { Parameters = params , Embedded = true, IsPCEventEmitter = true, Description = "Sends current value of given Digital Signal Hardware module to host"  }
end

HW_MODULE_CONTROLLER = function()
  local params = OrderedTable()
  params.module = {Type = "Integer"}
  params.state =  {Type = "Integer"}

  return   { Parameters = params , Embedded = true, Description = "Enables or disables given Hardware Module"  }
end

MOVE_LIMITS_SETTER = function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.x_min =  {Type = "Float"}
  params.y_min =  {Type = "Float"}
  params.z_min =  {Type = "Float"}
  params.x_max =  {Type = "Float"}
  params.y_max =  {Type = "Float"}
  params.z_max =  {Type = "Float"}

  return   { Parameters = params , Embedded = true , OptionalParams = {"x_min", "y_min", "z_min", "x_max", "y_max", "z_max"}
  , Description = "" 
      }
end

VALUE_DIFFERENCE_WAITER = function()
  local params = OrderedTable()
  params.source1 = {Type = "Integer"}
  params.source1_type =  {Type = "Integer"}
  params.source2 =  {Type = "Integer"}
  params.source2_type =  {Type = "Integer"}
  params.threshold =  {Type = "Float"}
  params.compare_type =  {Type = "Integer"}
  params.time_hysteresis =  {Type = "Float"}

  return   { Parameters = params , Embedded = true, Description = "Waits until 2 given values difference became greater/lesser than given threshold"  }
end

POSITION_DETECTOR = function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.px =  {Type = "Float"}
  params.py =  {Type = "Float"}
  params.pz =  {Type = "Float"}
  params.p =  {Type = "Vector"}
  params.threshold =  {Type = "Float"}
  params.op_type =  {Type = "Integer"} -- ??

  return   { Parameters = params , Embedded = true, OptionalParams = {"px", "py", "pz", "p"} , Description = "Waits until given Movable position became in given relation with given position" }
end

PARAM_NON_ZERO_WAITER = function()
  local params = OrderedTable()
  params.source = {Type = "ANY_LOWLEVEL"}
  params.time_hysteresis =  {Type = "Integer"}

  return   { Parameters = params , Embedded = true, OptionalParams = {"time_hysteresis"}, Description = "After started waits until given param become non-zero, then finishes"  }
end

PARAMETER_VALUES_SENDER = function()
  local params = OrderedTable()
  params.event = {Type = "PC_EVENT_ID"}
  params.param1 =  {Type = "ANY_LOWLEVEL"}
  params.param2 =  {Type = "ANY_LOWLEVEL"}
  params.param3 =  {Type = "ANY_LOWLEVEL"}
  params.param4 =  {Type = "ANY_LOWLEVEL"}
  params.param5 =  {Type = "ANY_LOWLEVEL"}
  params.param6 =  {Type = "ANY_LOWLEVEL"}
  params.param7 =  {Type = "ANY_LOWLEVEL"}
  params.param8 =  {Type = "ANY_LOWLEVEL"}
  params.param9 =  {Type = "ANY_LOWLEVEL"}
  params.param10 = {Type = "ANY_LOWLEVEL"}

  return   { Parameters = params, IsPCEventEmitter = true , Embedded = true , OptionalParams = {"param1", "param2", "param3", "param4", "param5", "param6", "param7", "param8", "param9", "param10"}
  , Description = "Sends up to 10 parameters to host machine"  }
end

MOVEMENT = function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.is_relative =  {Type = "Integer"}
  params.px =   {Type = "Float"}
  params.py =   {Type = "Float"}
  params.pz =   {Type = "Float"}
  params.vx =  {Type = "Float"}
  params.vy =  {Type = "Float"}
  params.vz =  {Type = "Float"}
  params.ax =  {Type = "Float"}
  params.ay =  {Type = "Float"}
  params.az =  {Type = "Float"}
  params.jerk_limit =  {Type = "Float"}
  params.accel_limit =  {Type = "Float"}
  params.drift_limit =  {Type = "Float"}
  params.speed_limit =  {Type = "Float"}
  params.max_dynamic_error =  {Type = "Float"}
  params.max_endpoint_error =  {Type = "Float"}
  params.T =  {Type = "Float"}

  params.p = {Type = "Vector"}
  params.v = {Type = "Vector"}
  params.a = {Type = "Vector"}

  return   { Parameters = params , Embedded = true , OptionalParams = {"px", "py", "pz", "vx", "vy", "vz", "ax", "ay", "az", "max_dynamic_error", "max_endpoint_error", "T", "p", "v", "a", "jerk_limit"}
  , Description = "Provides finely controlled movement from current position to given position" }
end

CONST_SPEED_MOVEMENT = function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.is_relative =  {Type = "Integer"}
  params.px =   {Type = "Float"}
  params.py =   {Type = "Float"}
  params.pz =   {Type = "Float"}

  params.speed_mag =   {Type = "Float"}
  
  params.max_dynamic_error =  {Type = "Float"}
  params.max_endpoint_error =  {Type = "Float"}
  params.T =  {Type = "Float"}

  params.p = {Type = "Vector"}
 

  return   { Parameters = params , Embedded = true , OptionalParams = {"px", "py", "pz", "max_dynamic_error", "max_endpoint_error", "T", "p", "speed_mag"}
  , Description = "Provides constant speed magnitude movement from current position to given position" }
end

CONST_ACCELERATION_MOVEMENT =  function()
    local params = OrderedTable()
    params.movable = {Type = "Integer"}
    params.is_relative =  {Type = "Integer"}
    params.x =   {Type = "Float"}
    params.y =   {Type = "Float"}
    params.z =   {Type = "Float"}
    params.acceleration =   {Type = "Float"}
    params.deceleration =   {Type = "Float"}
    params.max_speed =   {Type = "Float"}
    params.max_dynamic_error =   {Type = "Float"}
    params.max_endpoint_error =   {Type = "Float"}

    return   { Parameters = params , Embedded = true , OptionalParams = {"x", "y", "z", "deceleration", "max_speed", "max_dynamic_error", "max_endpoint_error"}
  , Description = "Provides constant acceleration magnitude movement from current position to given position" }
end

PARAMETRIC_MOVEMENT =  function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.p =  {Type = "Vector"}
  params.px =  {Type = "Float"}
  params.py =  {Type = "Float"}
  params.pz =  {Type = "Float"}
  params.time_param =   {Type = "Float", Mutable = true}
  
  params.max_dynamic_error =  {Type = "Float"}
  params.T =  {Type = "Float"}

  return   { Parameters = params , Embedded = true , OptionalParams = {"T", "p", "px", "py", "pz"}
  , Description = "Parametric movement. Animates 'time_param' from 0 to T, moves 'movable' according to 'p' vector param" }
end


HAL_REQUEST = function()
  local params = OrderedTable()
  params.requestType = {Type = "Integer"}
  params.message = {Type = "ByteString"}

  return   { Parameters = params , Embedded = true, Description = "Sends byte array message to HAL" }
end

return P
