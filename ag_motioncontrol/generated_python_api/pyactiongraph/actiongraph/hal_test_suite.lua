require"lua_actiongraph_utils"

local utils = require("utils")

local argparse = require "argparse"
local OrderedTable = require"orderedtable"
local json = require'json'
local actiongraph_rpc_proto = require"actiongraph_rpc_proto"
local scheduler = require"scheduler"
require"custom_lowlevel_functions"
SerialTransport = require"transport_wrapper".SerialTransport

local parser = argparse("lua_interpreter hal_test_suite.lua", "ActionGraph HAL test suite") 
parser:argument("test_name", "Test name to perform.", "all")
parser:option("-t --transport_config", "Serial transport connection string"):count(1)

local color = require"color"
local usecoloredoutput = true
local function C(str, clr, bold)
    if usecoloredoutput then
        if bold == true then
            return color.underline .. color.bold .. color.fg[clr] .. str .. color.reset
        else
            return color.fg[clr] .. str .. color.reset
        end
    end
    return str
end

local arguments = parser:parse(cmd_args)

local hb_count = 0
local rpc

local transport = SerialTransport()
if transport:open(arguments.transport_config) == false then
    print(C(string.format("CANNOT OPEN SERIAL TRANSPORT '%s'", arguments.transport_config), "red"))
    return
end

local serialSender = function (data)
    transport:sendData(data)
end

local eventQueue = scheduler.NewQueue()
local eventH = function(name)
    return function(args)
        eventQueue:put(setmetatable( {name = name, args = args}, {__tostring = function(v) return json.stringify(v) end}))
    end
end
rpc = actiongraph_rpc_proto.RPC(actiongraph_rpc_proto.parseRPCEndpoints(
    {
        {0, { {"version", "ui8"},},  eventH('STARTUP_DONE') },
        {1, { {"ts", "ui8"},},  eventH('HEARTBEAT')  },
        {3, { }, eventH('STARTING_SERIAL_TEST_UC_TO_PC') },

        {4, {{"counter", "ui4"}, {"data", "2a1"}}, eventH('SERIAL_TEST_DATA_NEXT_PACKET_1') },
        {5, {{"counter", "ui4"},  {"data", "2a2"}}, eventH('SERIAL_TEST_DATA_NEXT_PACKET_2') },
        {6, {{"counter", "ui4"},  {"data", "2a4"}}, eventH('SERIAL_TEST_DATA_NEXT_PACKET_4') },
        {7, {{"counter", "ui4"},  {"data", "2a8"}}, eventH('SERIAL_TEST_DATA_NEXT_PACKET_8') },
        {8, {{"counter", "ui4"},  {"data", "2a16"}}, eventH('SERIAL_TEST_DATA_NEXT_PACKET_16') },
        {9, {{"counter", "ui4"},  {"data", "2a32"}}, eventH('SERIAL_TEST_DATA_NEXT_PACKET_32') },
        {10, {{"counter", "ui4"}, {"data", "2a64"} }, eventH('SERIAL_TEST_DATA_NEXT_PACKET_64') },
        {11, {{"counter", "ui4"}, {"data", "2a86"} }, eventH('SERIAL_TEST_DATA_NEXT_PACKET_86') },
        {12, {{"hash", "2a8"}}, eventH('SERIAL_TEST_UC_TO_PC_END')},

        {14, { }, eventH('STARTING_SERIAL_TEST_PC_TO_UC') },
        {15, {{"hash", "2a8"}}, eventH('SERIAL_TEST_PC_TO_UC_END')},
        {16, { }, eventH('SERIAL_TEST_PC_TO_UC_RCVED') },
        {21, {}, eventH('STARTING_SERIAL_TEST_UC_TO_PC_RAW_SAW_DATA')},
        {22, {{"estimatedDelta", "f4"}, {"realEncoderDelta", "f4"} }, eventH('MEASURE_STEP_GENERATOR')}
    }
), {
    STARTUP_DONE=                                   {0, { } },
    SERIAL_TEST_UC_TO_PC=                           {2, { } },
    SERIAL_TEST_PC_TO_UC=                           {13, { } },
    SERIAL_TEST_PC_TO_UC_END=                       {15, { } },

    SERIAL_TEST_DATA_NEXT_PACKET_1  =  {4, {{"counter", "ui4"},  {"data", "2a1"} } },
    SERIAL_TEST_DATA_NEXT_PACKET_2  =  {5, {{"counter", "ui4"},  {"data", "2a2"} } },
    SERIAL_TEST_DATA_NEXT_PACKET_4  =  {6, {{"counter", "ui4"},  {"data", "2a4"} } },
    SERIAL_TEST_DATA_NEXT_PACKET_8  =  {7, {{"counter", "ui4"},  {"data", "2a8"} } },
    SERIAL_TEST_DATA_NEXT_PACKET_16 =  {8, {{"counter", "ui4"},  {"data", "2a16"} } },
    SERIAL_TEST_DATA_NEXT_PACKET_32 =  {9, {{"counter", "ui4"},  {"data", "2a32"} } },
    SERIAL_TEST_DATA_NEXT_PACKET_64 =  {10, {{"counter", "ui4"},  {"data", "2a64"} } },
    SERIAL_TEST_DATA_NEXT_PACKET_86 =  {11, {{"counter", "ui4"},  {"data", "2a86"} } },

    SERIAL_TEST_UC_TO_PC_RAW_SAW_DATA = {20, {} },
    MEASURE_STEP_GENERATOR = {22, {{"duration", "ui4"},  {"speedInputPin", "ui2"},  {"estimationOutputPin", "ui2"},  {"encoderOutputPin", "ui2"},  {"speed", "f4"},  {"mode", "ui1"} } }
})

local tests = OrderedTable()

tests.step_generator_test = function()
    print("Starting steps genrators testing")
    local useEncoder = true
    local encoderCoef = 2000/3200

    local pinconfs = {
        --{
        --    speedInputPin = 0,
        --    estimationOutputPin = 0,
        --    encoderOutputPin = 3,
        --},
        {
            speedInputPin = 1,
            estimationOutputPin = 1,
            encoderOutputPin = 4,
        },
        --{
        --    speedInputPin = 2,
        --    estimationOutputPin = 2,
        --    encoderOutputPin = 5,
        --}
        }
    CONSTANT_SPEED = 1
    CONSTANT_ACCELERATION = 0
    local cases = {
        {
            duration = 500,
            speed = 1000,
            mode = CONSTANT_SPEED
        },
        {
            duration = 50,
            speed = 10000,
            mode = CONSTANT_SPEED
        },
        {
            duration = 50,
            speed = -10000,
            mode = CONSTANT_SPEED
        },
        {
            duration = 500,
            speed = -1000,
            mode = CONSTANT_SPEED
        },
        {
            duration = 500,
            speed = 1000,
            mode = CONSTANT_ACCELERATION
        },
        {
            duration = 50,
            speed = 10000,
            mode = CONSTANT_ACCELERATION
        },
        {
            duration = 50,
            speed = -10000,
            mode = CONSTANT_ACCELERATION
        },
        {
            duration = 500,
            speed = -1000,
            mode = CONSTANT_ACCELERATION
        }
    }
    local retValue = true
    for _, pinconf in ipairs(pinconfs) do
        print(string.format("\n\n\nTesting generator (speedPin=%d, estimationPin=%d, encoderPin=%d\n)", pinconf.speedInputPin, pinconf.estimationOutputPin, pinconf.encoderOutputPin))
        for caseNo, caseData in ipairs(cases) do
            if caseData.mode == CONSTANT_ACCELERATION then
                print(string.format("Const acceleration->deceleration, Max. speed = %s steps/s, duration = %s s", caseData.speed, caseData.duration/1e3))
            elseif caseData.mode == CONSTANT_SPEED then
                print(string.format("Const Speed = %s steps/s, duration = %s s", caseData.speed, caseData.duration/1e3))
            else
                error("Unsupported step generator test mode")
            end
            rpc.send(serialSender, "MEASURE_STEP_GENERATOR",
                {
                    speedInputPin = pinconf.speedInputPin,
                    estimationOutputPin = pinconf.estimationOutputPin,
                    encoderOutputPin = pinconf.encoderOutputPin,
                    duration = caseData.duration,
                    speed = caseData.speed,
                    mode = caseData.mode
                }
            )
            local res
            while true do
                local e = eventQueue:get()
                if e.name == 'MEASURE_STEP_GENERATOR' then
                    res = e.args
                    break
                end
            end
            local expectedDisplacement
            if caseData.mode == CONSTANT_ACCELERATION then
                expectedDisplacement = (caseData.speed*caseData.duration/1000) / 2.0
            elseif caseData.mode == CONSTANT_SPEED then
                expectedDisplacement = caseData.speed*caseData.duration/1000
            end
            local estimRelativeError =  res.estimatedDelta / expectedDisplacement - 1
            local estimEncError = res.realEncoderDelta / (expectedDisplacement*encoderCoef) - 1

        

            if math.abs(estimRelativeError) > 0.02 then
                print(C(string.format("Relative error for estimated steps count exceeds 2%%: %.2f %%", estimRelativeError * 100), "red"))
                retValue = false
            else
                print(string.format("Steps estimated count relative error: %.2f %%", estimRelativeError * 100))
            end

            if useEncoder then
                if math.abs(estimEncError) > 0.02 then
					print(C(string.format("Relative error for encoder steps count exceeds 2%%:  %.2f %%", estimEncError * 100), "red"))
                    retValue = false
                else
                    print(string.format("Steps encoder-nased count relative error: %.2f %%", estimEncError * 100))
                end
            end
            print()
        end
    end
    return retValue
end
tests.uc_pc_raw_saw_data_stress_test = function()
    print("Starting serial port uc->pc raw data stress testing")

    rpc.send(serialSender, "SERIAL_TEST_UC_TO_PC_RAW_SAW_DATA")
    print("\twaiting test start confirmation")
    while true do
        local e = eventQueue:get()
        if e.name == 'STARTING_SERIAL_TEST_UC_TO_PC_RAW_SAW_DATA' then
            print(C("..done", "green"))
            break
        end
    end
    local ts = millis()
    local expectedVal = 0
    local rcvCounter = 0
    local rcvTs = millis()
    local restFromPrev = ""
    local totalRcv = 0
    while true do
        local rcv = transport:readData()
        if rcv ~= nil then
            rcvCounter = rcvCounter + #rcv
            totalRcv = totalRcv + #rcv
            ts = millis()
            rcv = restFromPrev .. rcv
            if #rcv % 2 ~= 0 then
                restFromPrev = rcv:sub(#rcv - 1, #rcv)
                rcv = rcv:sub(1, #rcv - 1)
            end
            for i = 1,#rcv / 2 do
                local ctr = parseBinaryRPCargument(rcv:sub(i*2 - 1, i*2), "ui2")
                if ctr ~= expectedVal then
                    print(C(string.format("TEST FAILED.  Expected counter: %s, got: %s", expectedVal, ctr ), "red"))
                    return false
                end
                if expectedVal == 65535 then
                    expectedVal = 0
                else
                    expectedVal = expectedVal + 1
                end
            end
        
        else
            delay(5)
        end
        if millis() - rcvTs > 1000 then
            print("\t", string.format("%s bytes per second", rcvCounter))
            rcvCounter = 0;
            rcvTs = millis()
        end
        if millis() - ts > 2000 then
            print(C("TEST SUCCESS. observed correct saw pattern, received "..totalRcv.." bytes", "green"))
            return true
        end
    end

    return false
end

tests.echo_test =  function()
    print("Starting serial port echo testing. RPC is not used, sending bytes 128-255")

    local function stepData(length)
        if length > 128 then
            length = 128
        end
        local res = ""
        for i = 1, length do
            res = res .. string.char(127 + i)
        end
	    return res
    end

    for pass = 1, 100 do
        print("Pass #"..pass)
        for data_length = 1,128 do
            local data = stepData(data_length)
            -- print(utils.tohex(data))
            transport:sendData(data)
            local ts = millis()
            local total_rcv = ""
            while true do
                local rcv = transport:readData()
                
                if rcv ~= nil then
                    total_rcv = total_rcv..rcv

                    if  total_rcv == data then
                        break
                    end
                    if # total_rcv > # data then
                        print(C(string.format("TEST FAILED. more data received then needed. Expected: %s, got: %s", utils.tohex(data), utils.tohex(total_rcv)), "red"))
                        return false
                    end
                else
                    delay(5)
                end
                if millis() - ts > 5000 then
                    print(C(string.format("TEST FAILED. echo is not received within 5 seconds. Expected: %s, got: %s", utils.tohex(data), utils.tohex(total_rcv)), "red"))
                    return false
                end
            end
        end
    end

    print(C("TEST SUCCESS. All sent bytes were echoed back", "green"))
    return true
end


tests.serialport_uc_to_pc = function()
    print("Starting serial port UC->PC transmission max performance testing.")
    
    rpc.send(serialSender, "SERIAL_TEST_UC_TO_PC")
    print("\twaiting test start confirmation")
    while true do
        local e = eventQueue:get()
        if e.name == 'STARTING_SERIAL_TEST_UC_TO_PC' then
            print(C("..done", "green"))
            break
        end
    end
    local msgs_with_data = {
        SERIAL_TEST_DATA_NEXT_PACKET_1 = true,
        SERIAL_TEST_DATA_NEXT_PACKET_2 = true,
        SERIAL_TEST_DATA_NEXT_PACKET_4 = true,
        SERIAL_TEST_DATA_NEXT_PACKET_8 = true,
        SERIAL_TEST_DATA_NEXT_PACKET_16 = true,
        SERIAL_TEST_DATA_NEXT_PACKET_32 = true,
        SERIAL_TEST_DATA_NEXT_PACKET_64 = true,
        SERIAL_TEST_DATA_NEXT_PACKET_86 = true,
    }
    local data_to_hash = ""
    local expected_hash = ""

    local rcv_cnt = 0
    local tsZeroRcved = 0
    scheduler.addTask(function()
        while expected_hash=="" do
            
            
            if rcv_cnt == 0 then
                if tsZeroRcved == 0 then
                    tsZeroRcved = millis()
                end
            else
                tsZeroRcved = 0
            end
            if tsZeroRcved ~= 0 and millis() - tsZeroRcved > 10000 then
                print(string.format("WARNING! no data received for %ss, looks like major problem. Try to restart the Target and the Suite",  (millis() - tsZeroRcved)/1e3))
            else
                print(string.format("\t\t\t receiving %s bytes/second", rcv_cnt))
            end
            rcv_cnt = 0
            scheduler.sleep(1)
        end
    end)

    local counter = 0
    local prevCheckCounter = 0
    while true do
        local e = eventQueue:get()
        if msgs_with_data[e.name]  == true then
            data_to_hash = data_to_hash .. serialiseBinaryRPCargument(e.args.counter, "ui4") .. e.args.data
            rcv_cnt = rcv_cnt + #e.args.data
            counter = counter + 1
            if prevCheckCounter ~= e.args.counter then
                print(C(string.format("TEST FAILED. wrong counter in message: expected %s, got %s", prevCheckCounter, e.args.counter), "red"))
                return false
            end
            prevCheckCounter = prevCheckCounter + 1
        elseif e.name == 'SERIAL_TEST_UC_TO_PC_END' then
            expected_hash = e.args.hash
            break
        else
            print("Unexpected message")
            return false
        end
    end

    local actualHash = memory64bitHash(data_to_hash)
    if actualHash ~= expected_hash then
        print(C(string.format("TEST FAILED. expected and actual hashes don't match. Received %s RPC requests", counter), "red"))
        return false
    else
        print(C(string.format("TEST SUCCESS. Hashes match. Received %s RPC requests", counter), "green"))
        return true
    end
    
end
tests.serialport_pc_to_uc = function()
    print("Starting serial port PC->UC  transmission with confirmation max performance testing.")
    
    rpc.send(serialSender, "SERIAL_TEST_PC_TO_UC")
    print("\twaiting test start confirmation")
    while true do
        local e = eventQueue:get()
        if e.name == 'STARTING_SERIAL_TEST_PC_TO_UC' then
            print(C("..done", "green"))
            break
        end
    end

    local function randomData(length)
        local res = ""
        for i = 1, length do
            res = res .. string.char(math.random(1, 255))
        end
	    return res
    end

    local totalSentData = ""
    local pkg_types = {
        {name = "SERIAL_TEST_DATA_NEXT_PACKET_1", size = 1},
        {name = "SERIAL_TEST_DATA_NEXT_PACKET_2", size = 2},
        {name = "SERIAL_TEST_DATA_NEXT_PACKET_4", size = 4},
        {name = "SERIAL_TEST_DATA_NEXT_PACKET_8", size = 8},
        {name = "SERIAL_TEST_DATA_NEXT_PACKET_16", size = 16},
        {name = "SERIAL_TEST_DATA_NEXT_PACKET_32", size = 32},
        {name = "SERIAL_TEST_DATA_NEXT_PACKET_64", size = 64},
        {name = "SERIAL_TEST_DATA_NEXT_PACKET_86", size = 86}
    }
    local prev_ts = millis()
    local send_cnt = 0
    for pkg_cnt = 1, 10000 do
        local pkg_type = pkg_types[math.random(1, 8)]
        local d = randomData(pkg_type.size)
        rpc.send(serialSender, pkg_type.name, {counter = pkg_cnt, data = d})
        totalSentData = totalSentData .. d
        send_cnt = send_cnt + #d
        local e = eventQueue:get()
        if e.name ~= 'SERIAL_TEST_PC_TO_UC_RCVED' then
            print("Unexpected message")
            return false
        end
        if millis() - prev_ts > 1000 then
            print(string.format("\t\t\t confirmed PC-UC transfer rate: %.0f bytes/second", send_cnt/((millis() - prev_ts)/1e3)))
            send_cnt = 0;
            prev_ts = millis();
        end
    end


    
    rpc.send(serialSender, "SERIAL_TEST_PC_TO_UC_END")
    print("\twaiting test end report")
    local expected_hash
    while true do
        local e = eventQueue:get()
        if e.name == 'SERIAL_TEST_PC_TO_UC_END' then
            expected_hash = e.args.hash
            print(C("..done", "green"))
            break
        end
    end
    local actualHash = memory64bitHash(totalSentData)
    if actualHash ~= expected_hash then
        print(C("TEST FAILED. expected and actual hashes don't match", "red"))
        return false
    else
        print(C("TEST SUCCESS. Hashes match", "green"))
        return true
    end
    
    return true
end

local finished = false
local function main()
    print("Actiongraph HAL testing suite.\n\n## Ensure that target is flashed with HAL testing firmware (HAL + libag_hal_test_suite library + call to 'ActionGraphHALTestSuiteMain') ##\n\n")
    local test_names = {}
    if arguments.test_name == "all" then
        print("Running all tests")
        for k, v in pairs(tests) do table.insert(test_names, k) end
    else
        if type(arguments.test_name) == "string" then
            arguments.test_name = {arguments.test_name}
        end
        for _, test_name in ipairs(arguments.test_name) do
            if tests[test_name] == nil then
                print(C(string.format("Unknown test '%s', skipping", test_name), "red"))
            else
                table.insert(test_names, test_name)
            end
        end
    end
    if #test_names == 0 then
        print("No tests to run, exiting")
        return
    end

    print("\n\nWaiting for initial sync message")
    scheduler.sleep(1)
    rpc.send(serialSender, "STARTUP_DONE")
    while true do
        local e = eventQueue:get()
        if e.name == 'STARTUP_DONE' then
            print(C("..done", "green"))
            break
        end
    end

    local successCount = 0
    local totalTestsCount = #test_names
    for test_i, test_name in ipairs(test_names) do
        print(C(string.format("\n\n%s) '%s'\n", test_i, test_name), "blue", true))
        if (tests[test_name])() == true then
            successCount = successCount + 1
        end
    end
    if successCount == totalTestsCount then
        print(C(string.format("\n\n####### ALL %s TESTS PASSED:) #######", totalTestsCount), "green"))
    else
        print(C(string.format("\n\n####### FAILED %s of %s TESTS :( #######",  totalTestsCount - successCount, totalTestsCount), "red"))
    end
    finished = true
end

scheduler.addTask(main, "main")
scheduler.addTask(function()
    while true do
        local new_data = transport:readData()
        if new_data ~= nil then
            rpc.addRawData(new_data)
        end
        scheduler.sleep(0)
    end
end, "ag rpc receiver")

scheduler.run(function() return not finished end)

