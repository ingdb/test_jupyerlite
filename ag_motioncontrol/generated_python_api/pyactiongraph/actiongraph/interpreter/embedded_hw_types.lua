local P = {}   -- package

local OrderedTable = require"orderedtable"

local globalEnv = _ENV
local _ENV = P

ANALOG_OUTPUT_SIGNAL = function () 
  local params = OrderedTable()
  params.hal_id = {Type = "Integer"}
  params.scale =  {Type = "Float"}
  params.offset = {Type = "Float"}
  params.initialValue = {Type = "Float"}

  return   { Parameters = params , Embedded = true, Description = "Allows to use hardware analog outputs. See board documentation for pin mapping and details" }
end 
ANALOG_INPUT_SIGNAL  = function () 
  local params = OrderedTable()
  params.hal_id = {Type = "Integer"}
  params.scale =  {Type = "Float"}
  params.offset = {Type = "Float"}

  return   { Parameters = params , Embedded = true, Description = "Allows to use hardware analog inputs. See board documentation for pin mapping and details"  }
end 

BASIC_PID_CONTROLLER = function () 
  local params = OrderedTable()
  params.control_signal = {Type = "Integer"}
  params.feedback_signal =  {Type = "Integer"}
  params.P = {Type = "Float"}
  params.I = {Type = "Float"}
  params.D = {Type = "Float"}
  params.resolution = {Type = "Float"}
  return   { Parameters = params , Embedded = true, Description = "Provides Movable entity using PID controller inside. Requires 1 analog signal for control and 1 for feedback"  }
end


MOVABLE_SIGNAL = function () 
  local params = OrderedTable()
  params.signal0 = {Type = "Integer"}
  params.signal1 = {Type = "Integer"}
  params.signal2 = {Type = "Integer"}
 
  return   { Parameters = params , Embedded = true, Description = "Exposes up to 3 ANALOG_OUTPUT_SIGNAL modules as a virtual Movable", OptionalParams = {"signal1", "signal2"} }
end


LINEAR_DELTA_ROBOT  = function () 
  local params = OrderedTable()
  params.actuator_offset = {Type = "Float"}
  params.actuator_elevation = {Type = "Float"}
  params.forearm_l = {Type = "Float"}
  params.ljo = {Type = "Float"}

  params.actuator0 = {Type = "Integer"}
  params.actuator1 = {Type = "Integer"}
  params.actuator2 = {Type = "Integer"}

  return   { Parameters = params , Embedded = true, Description = "Movable module for Delta robot with linear actuators" }

end

PERPENDICULAR_AXES_ROBOT  = function () 
    local params = OrderedTable()
    params.actuator0 = {Type = "Integer"}
    params.actuator1 = {Type = "Integer"}
    params.actuator2 = {Type = "Integer"}
  
    return   { Parameters = params , Embedded = true, Description = "Movable module for Delta robot with linear actuators" }
  
  end

ROTATING_DELTA_ROBOT = function () 
  local params = OrderedTable()
  params.upperarm_l = {Type = "Float"}
  params.ujo = {Type = "Float"}
  params.forearm_l = {Type = "Float"}
  params.ljo = {Type = "Float"}

  params.actuator0 = {Type = "Integer"}
  params.actuator1 = {Type = "Integer"}
  params.actuator2 = {Type = "Integer"}

  return   { Parameters = params , Embedded = true, Description = "Movable module for Delta robot with rotating arms" }

end


DIGITAL_OUTPUT_SIGNAL = function () 
  local params = OrderedTable()
  params.hal_id = {Type = "Integer"}
  params.initialValue = {Type = "Integer"}
  return   { Parameters = params , Embedded = true , Description = "Allows to use hardware digital outputs. See board documentation for pin mapping and details" }
end 

DIGITAL_INPUT_SIGNAL  = function () 
  local params = OrderedTable()
  params.hal_id = {Type = "Integer"}
  return   { Parameters = params , Embedded = true, Description = "Allows to use hardware digital inputs. See board documentation for pin mapping and details"  }
end 

MOVABLE_COORD_SYSTEM_TRANSFORM = function()
  local params = OrderedTable()
  params.movable = {Type = "Integer"}
  params.speed_limit = {Type = "Float"}

  params.translation_x = {Type = "Float"}
  params.translation_y = {Type = "Float"}
  params.translation_z = {Type = "Float"}
  params.translation = {Type = "Vector"}

  params.rot_axis_x = {Type = "Float"}
  params.rot_axis_y = {Type = "Float"}
  params.rot_axis_z = {Type = "Float"}
  params.rot_axis = {Type = "Vector"}

  params.rot_angle = {Type = "Float"}

  params.scale_x = {Type = "Float"}
  params.scale_y = {Type = "Float"}
  params.scale_z = {Type = "Float"}
  params.scale = {Type = "Vector"}


  return   { Parameters = params , Embedded = true, Description = "Movable module for coordinates transformation of another Movable" }

end

DIGITAL_PULSES_GENERATOR = function () 
    local params = OrderedTable()
    params.hal_id = {Type = "Integer"}
    params.frequency = {Type = "Float"}
    params.expression = {Type = "Integer"}

    return   { Parameters = params , Embedded = true, Description = "Timer-interrupts driven digital signal generator" }
end

ANALOG_SIGNAL_GENERATOR = function () 
    local params = OrderedTable()
    params.hal_id = {Type = "Integer"}
    params.frequency = {Type = "Float"}
    params.expression = {Type = "Float"}

    return   { Parameters = params , Embedded = true, Description = "Timer-interrupts driven analog signal generator" }
end
return P
