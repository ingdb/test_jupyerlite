local utils = require("utils")
local pathlib = require'pl.path'

local microsteps_count = 16
local max_motor_steps_per_sec = 1000000
local motor_single_step_angle =  math.pi * 2.0 / 200.0/microsteps_count

local motor_count = parameters.motorCount or 1

local motors = {}


for id = 0,motor_count-1 do
    local m = {
        posFeedbackStepsSignal = simulator.InputAnalogSignal(id),
        stallSignal = simulator.InputDigitalSignal(id),
        motorControlSignal = simulator.OutputAnalogSignal(id),
        homingResetSignal = simulator.OutputDigitalSignal(id+1000),
        motor_position = 0
    }
    m.motorControlSignal.onChanged(function(val) 
        -- utils.print(string.format("'%s' analog signal '%s': %s", HAL.RobotUniqueSerialNumber(), id, val))
    end)
    table.insert(motors, m)


    m.stallSignal.set(false)
    m.posFeedbackStepsSignal.set(  math.floor(m.motor_position/motor_single_step_angle ))
end

local emergencyStopSignal = simulator.InputDigitalSignal(66)
UI.Key(emergencyStopSignal, {idle_value=false})
UI.Graph({emergencyStopSignal}, {window = 5})

local testGPIOIns = {}
local testGPIOOuts = {}
for id = 1,5 do 
    local sigIn = simulator.InputDigitalSignal(30+id)
    local sigOut = simulator.OutputDigitalSignal(20+id)
    sigOut.onChanged(function(val) 
        utils.print(string.format("'%s' GPIO '%s' written: %s", HAL.RobotUniqueSerialNumber(), id, val))
    end)
    table.insert(testGPIOIns, sigIn)
    table.insert(testGPIOOuts, sigOut)
    UI.Bulb(sigOut)
    UI.Switch(sigIn)
end


for _, m in ipairs(motors) do
    UI.Bulb(m.homingResetSignal)
end

if parameters.showMotorPosGraphs == true then
    for _, m in ipairs(motors) do
        UI.Graph({m.posFeedbackStepsSignal}, {window = 5})
    end
end

if parameters.showMotorSpeedGraphs == true then
    for _, m in ipairs(motors) do
        UI.Graph({m.motorControlSignal}, {window = 5})
    end
end

if parameters.showMotorStallStates == true then
    for _, m in ipairs(motors) do
        UI.Bulb(m.stallSignal)
    end
end

local function speedCrop(value)
    if value == "n/a" then
        value = 0
    end
    local speed = value
    if speed >= max_motor_steps_per_sec then
        speed = max_motor_steps_per_sec
    end
    if speed <= -max_motor_steps_per_sec then
        speed = -max_motor_steps_per_sec
    end
    return speed
end


local prevTickTime = -1
simulator.Register_Tick(function ()
    if prevTickTime == -1 then 
        prevTickTime = HAL.CurrentMicroseconds()/1e6
    end
    local currentT = HAL.CurrentMicroseconds()/1e6
    local deltaS = currentT - prevTickTime
   
    for i = 1,motor_count,1 do 
        local m = motors[i]
        local motor_speed = speedCrop(m.motorControlSignal.get()) * motor_single_step_angle
        m.motor_position = m.motor_position + motor_speed*deltaS
        m.posFeedbackStepsSignal.set(  math.floor(m.motor_position/motor_single_step_angle ))

        local r =  m.motor_position <= -3.14159/4.0 or m.motor_position >= 3.14159/4.0
        if r then
            -- utils.print(string.format("SwitchSensor %s activated at %s: %s", i, HAL.CurrentMicroseconds(),  m.motor_position))
        end
        m.stallSignal.set(r)
    end

    prevTickTime = currentT
end)

simulator.Register_HALRequest(101, function(requestType, data)
    utils.print("HAL request for homing", utils.tohex(data))
    return 0, ""
end)

simulator.Register_HALRequest(0, function(requestType, data)
    utils.print("HAL 0", utils.tohex(data))
    return 0, ""
end)

simulator.Register_HALRequest(1, function(requestType, data)
    utils.print("HAL 1", utils.tohex(data))
    return 0, ""
end)

simulator.Register_HALRequest(2, function(requestType, data)
    utils.print("HAL 2", utils.tohex(data))
    return 0, ""
end)

simulator.Register_HALRequest(3, function(requestType, data)
    utils.print("HAL 2", utils.tohex(data))
    return 0, ""
end)

simulator.Register_HALRequest(128, function(requestType, data)
    utils.print("HAL request example handler with return data", utils.tohex(data))
    return 0, "aabbdead"
end)

simulator.Register_HALRequest(129, function(requestType, data)
    utils.print("HAL request example handler without return data", utils.tohex(data))
    return 0, ""
end)

simulator.Register_HALRequest(666, function(requestType, data)
    utils.print("HAL request handler 666")
    if #data ~= 2 then return 2, "" end
    local pin = unpackValueFromBinary(data:sub(1, 1), "ui1")
    local state = unpackValueFromBinary(data:sub(2, 2), "ui1")
    utils.print(string.format("HAL request example handler GPIO config,  pin %s to state %s", pin, state))
    return 0, ""
end)


simulator.Register_ReadPersistentMemory(function (offset, size)
    if parameters.permanentStorage ~= true then
        return false, ""
    end
    local ser = utils.tohex(HAL.RobotUniqueSerialNumber())
    local abspath = pathlib.join(thisScriptPath, "flash_memory_"..ser..".bin")
    local f = io.open(abspath, "rb")
    if f ~= nil then
        local data = f:read('a')
        f:close()
        if string.len(data) >= size then
            local ret = string.sub(data, 1, size)
            utils.print("read ", size, " bytes from persistent storage")
            return true, ret
        end
    end
    return false, ""
end)

simulator.Register_WritePersistentMemory(function (offset, data)
    if parameters.permanentStorage ~= true then
        return true
    end
    local ser = utils.tohex(HAL.RobotUniqueSerialNumber())
    local abspath = pathlib.join(thisScriptPath, "flash_memory_"..ser..".bin")
    local f = io.open(abspath, "wb")
    if f ~= nil then
        local _, err = f:write(data)
        f:close()
        if err == nil then
            delay(2000)
            utils.print("written ", string.len(data), " bytes to persistent storage")
        else
            utils.print("HAL WritePersistentMemory failed: ", err)
        end
    else
        utils.print("HAL WritePersistentMemory failed")
    end
    return true
end)