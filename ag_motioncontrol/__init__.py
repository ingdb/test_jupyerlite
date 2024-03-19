import asyncio
from .generated_python_api import API
from .generated_python_api.pyactiongraph.launcher import lua_python_binding, _fromLua
from .generated_python_api.pyactiongraph.actiongraphvm_utils import calculate_movement_time
from os import path
from .hal_api import HAL_API
class MotionController:
    """
    Call :meth:`~MotionController.start` to open the connection.

    :param str robot_serial:
        The serial ID of the robot to connect to.
        Useful to differentiate between multiple connected robots.
    :param str manual_transport_config:
        The selected transport configuration. Use 'simulation' to connect to the simulator.
    """
    def __init__(self, robot_serial, manual_transport_config=None, force_reset=False, debug_log_level=0, additional_client_rpc_connections=[], additional_simulator_rpc_connections={}) -> None:
        if manual_transport_config == "simulation":
            simulation = True
            manual_transport_config = None
        else:
            simulation = False
        self.generated_api = API(
            robot_serial_number=robot_serial,
            robot_manual_transport=manual_transport_config,
            robot_additional_simulator_rpc_connections=additional_simulator_rpc_connections,
            additional_client_rpc_connections=additional_client_rpc_connections,
            debug_logging=debug_log_level,
            force_reset=force_reset,
            simulation=simulation,
        )

        self.session_counter = 1
        self.sessions = dict()

        self.rpc_handler_task = None
        self.current_positions = dict()

        for i in range(1,10):
             self.current_positions[i] = {
                'pos': 0,
                'ts': 0
            }
        async def notifications_reader():
            async with self.notifications() as n:
                async for msg in n:
                    if msg['type'] == 'pos_feedback':
                        self.current_positions[msg['args']['axis']] = {
                            'pos': msg['args']['pos'],
                            'ts': msg['args']['ts']
                        }
                        # print("Cur pos update: ", self.current_positions)
                        
        self.pos_feedback_collection_task = asyncio.create_task(notifications_reader())

        self.HAL = HAL_API(self.generated_api)

    def get_axis_pos(self, index):
        return self.current_positions[index]['pos']

    async def write_rpc(self, m):
        if 'command' not in m:
            m["command"] = "user_custom_rpc"
        if 'args' not in m:
            m["args"] = {}
        # print("write_rpc", m)
        await self.generated_api.send_rpc_msg(m)


    async def ticker(self):            
        while True:
            message =  await self.generated_api.receive_rpc_msg()
            if "command" in message and message["command"] == "user_custom_rpc":
                if message["session_id"] in self.sessions:
                    for q in self.sessions[message["session_id"]]:
                        q.put_nowait(message)
                else:
                    print("Unhandled message", message)
                
    async def start(self):
        """
        Start the motion controller. It is recommended to call :meth:`~MotionController.wait_for_ready` before executing any movements.
        """
        self.generated_api.start()

        self.rpc_handler_task = asyncio.create_task(self.ticker())

    async def stop(self):
        """
        Close the connection to the robot.
        """
        self.pos_feedback_collection_task.cancel()
        await self.generated_api.stop()

        if self.rpc_handler_task:
            if not self.rpc_handler_task.done():
                self.rpc_handler_task.cancel()
            try:
                await self.rpc_handler_task
            except asyncio.CancelledError:
                pass
            except Exception as e:
                print("Exited rpc_handler_task with exception: ", e)
                raise e

    def request(self, req, timeout=20):
        return Session(req, self, timeout)

    def notifications(self):
        return Session(None, self, None, explicit_id="")

    def next_id(self):
        self.session_counter += 1
        return str(self.session_counter)

    async def set_coordinate_transform(self, axis, scale=1.0, home_position=0, triggered_homing_speed=None):
        """
        Sets axis scale and homing zero offset and performs homing

        :param int axis:
            Axis index, 1, 2 or 3

        :param float scale:
            Scale factors of the axis, where base unit is meter. 100 means switching axis to cantimeters. 
            Negative value inverts axis direction.

        :param float home_position:
            Position of homing sensor

        :param float triggered_homing_speed:
            The speed of homing
        """
        p_scale = getattr(self.generated_api.robot, f"Hardware_Motor{axis-1}_user_defined_scale_param")
        await p_scale.set(scale)
        p_offest = getattr(self.generated_api.robot, f"Graph_a{axis-1}_calibrater_actuatorZeroPos_param")
        await p_offest.set(home_position)
        await self.do_homing(axis, speed=triggered_homing_speed)

    async def do_homing(self, axis, speed=None):
        r =  {
            "args": {
                "axis": axis,
            },
            "type": "do_homing"
        }
        if speed is not None:
            r["args"]["speed"] = speed
        async with self.request(r) as req:
            await req.wait_success()

    async def execute_movements(self, mv_sequence, max_jerk=None, max_acceleration=None, max_speed=None, return_on_empty_queue=False):
        """
        Execute a sequence of movements.

        :param list mv_sequence:
            The list of movements to be executed in sequence. Every element is either a dictionary
            specifing which axis should be moved to what position or a list of such dictionaries
            targeting multiple axes. In the latter case the movements of the different axes are
            executed in parallel.

        :param float max_jerk:
            The robot's maximum jerk, i.e. rate of change of acceleration during the sequence of movements.
            Defaults to 100m/s^3.

        :param float max_acceleration:
            The robot's maximum acceleration during the sequence of movements.
            Defaults to 20m/s^2.

        :param float max_speed:
            The robot's maximum speed during the sequence of movements.
            Defaults to 10m/s.
        """
        _utils = lua_python_binding.require("utils")
        if isinstance(_utils, tuple):
            _utils = _utils[0]
        this_path = path.dirname(path.abspath(__file__))
        defaults =  _utils.parseYAMLFile(path.join(this_path, "defaults","movements.yaml"))
        if defaults is None:
            defaults = {
                "max_jerk": 100,
                "max_acceleration": 20,
                "max_speed": 10
            }
        else:
            defaults = _fromLua(defaults)
        if max_jerk is not None:
            defaults['max_jerk'] = max_jerk
        if max_acceleration is not None:
            defaults['max_acceleration'] = max_acceleration
        if max_speed is not None:
            defaults['max_speed'] = max_speed

        def fill_params(d):
            if 'max_jerk' not in d:
                d['max_jerk'] = defaults['max_jerk']
            if 'max_acceleration' not in d:
                d['max_acceleration'] = defaults['max_acceleration']
            if 'max_speed' not in d:
                d['max_speed'] = defaults['max_speed']
        mv_req_data = []

        prev_axis_positions = dict()
        for k, v in self.current_positions.items():
            prev_axis_positions[k] = v['pos']

        for sequence_elem in mv_sequence:
            used_ids = set()
            if isinstance(sequence_elem, dict):
                d = dict(**sequence_elem)
                fill_params(d)
                prev_axis_positions[d['axis']] = d['position']
                mv_req_data.append([d])
            elif isinstance(sequence_elem, list):
                MaxT = 0
                T_is_set_explicitely = False
                for seq_mv_data in sequence_elem:
                    if 'T' in seq_mv_data:
                        if T_is_set_explicitely is True:
                            raise AttributeError("Pass T only single time in parallel movement batch")
                        T_is_set_explicitely = True
                        MaxT = seq_mv_data['T']
                semiprepared = []
                for seq_mv_data in sequence_elem:
                    d = dict(**seq_mv_data)
                    if d['axis'] in used_ids:
                        raise ValueError("Cannot have duplicate ids in single synchronous movement batch")
                    used_ids.add(d['axis'])
                    fill_params(d)
                    start_pos = prev_axis_positions[d['axis']]
                    end_pos = d['position']
                    if T_is_set_explicitely is False:
                        calculation_params = {
                            "DriftMax": 0, 
                            "JMax": d['max_jerk'], 
                            "AMax": d['max_acceleration'], 
                            "SpeedMax": d['max_speed'], 
                            "P0": [start_pos, 0, 0],
                            "V0": [0, 0, 0],
                            "A0": [0, 0, 0],
                            "P1": [end_pos, 0, 0],
                            "V1": [0, 0, 0],
                            "A1": [0, 0, 0]
                        }
                        t, err = calculate_movement_time(**calculation_params)
                        if err is not None:
                            raise ValueError("Movement time calculation failed")
                        if t > MaxT:
                            MaxT = t
                    semiprepared.append(d)
                    prev_axis_positions[d['axis']] = d['position']
                for d in semiprepared:
                    d['T'] = MaxT
                mv_req_data.append(semiprepared)
            else:
                raise ValueError("Pass movements or movements lists here")
        for req_data in mv_req_data: #glitches are possible?
            async with self.request( { 
                "args": {
                    "movements": req_data
                },
                "type": "enqueue_movements"
            }) as req:
                # await req.wait_success()
                async for m in req:
                    if return_on_empty_queue and m['type'] == 'movement_queue_state' and m['args']['size'] == 0:
                        break

                    pass
                    # print(m)
                    # if m["type"] == "movement_finished":
                    #     print(f"Axis {m['args']['axis']} -> {m['args']['pos']}")
        
    async def wait_for_ready(self):
        """
        Wait for the robot to signal it is ready.

        If no signal is given within 30 seconds an exception is raised.
        """
        from time import time
        ts = time()
        while True:
            ok = False
            async with self.request({"type": "connection_status_request" }) as req:
                async for m in req:
                    if m["args"]["is_online"] == True:
                        ok = True
            if ok:
                break
            await asyncio.sleep(1)
            if time() - ts > 30:
                raise Exception("No connection for 30 seconds, exiting")
        await asyncio.sleep(0.1)

    async def read_gpio(self, pin):
        """
        Read the value of a GPIO pin.

        :param int pin:
            Pin number for the desired pin.
        :return: The state of the selected pin.
        :rtype: int
        """
        await self.generated_api.robot.Hardware_GPIOControlModule_hal_id_param.set(pin)
        await self.generated_api.robot.READ_GPIO_event.send()
        return (await self.generated_api.robot.GPIO_DIN_VALUE_event)['value']
    
    async def write_gpio(self, pin, value):
        """
        Set the value of a GPIO pin.

        :param int pin:
            Pin number for the desired pin.
        :param bool value:
            Digital value the pin should be set to (truthy value for HIGH, falsy for LOW).
        """
        if value:
            value = 1
        else:
            value = 0
        await self.generated_api.robot.Hardware_GPIOControlModule_hal_id_param.set(pin)
        await self.generated_api.robot.Graph_gpioControl_gpioValueToWrite_param.set(value)
        await self.generated_api.robot.WRITE_GPIO_event.send()

    async def set_pos_feedback_frequency(self, axis, freq=30):
        await getattr(self.generated_api.robot, f"Graph_a{axis-1}_positionReporter_stopper_event").send()
        if freq > 0:
            await getattr(self.generated_api.robot, f"Graph_a{axis-1}_positionReporter_frequency_param").set(freq)
            await getattr(self.generated_api.robot, f"Graph_a{axis-1}_positionReporter_starter_event").send()

class RequestError(Exception):
    def __init__(self, request_args):
        self.request_args = request_args
        super().__init__(self.request_args["error"])

class RequestConcurrentAccessError(Exception):
    def __init__(self):
        super().__init__()

class RequestNotSentError(Exception):
    def __init__(self):
        super().__init__()

class Session:
    def __init__(self, req, api, timeout, explicit_id=None) -> None:
        self.api = api
        self.queue = asyncio.Queue()
        self.req = req
        self.timeout = timeout
        self.finished = False
        self.in_progress = False
        self.explicit_id = explicit_id

    async def __aenter__(self):
        if self.in_progress == True:
            raise RequestConcurrentAccessError()
        if self.explicit_id == None:
            self.id = self.api.next_id()
        else:
            self.id = self.explicit_id
        if self.id not in self.api.sessions:
            self.api.sessions[self.id] = set()
        self.api.sessions[self.id].add(self.queue)
        self.finished = False
        self.in_progress = True
        if self.req is not None:
            self.req["session_id"] = self.id
            self.req["command"] = "user_custom_rpc"
            await self.api.write_rpc(self.req)
        return self

    async def __aexit__(self,  *args):
        self.api.sessions[self.id].remove(self.queue)
        self.in_progress = False

    def __aiter__(self):
        if self.in_progress == False:
            raise RequestNotSentError()
        return self

    async def __anext__(self):
        if self.finished:
            raise StopAsyncIteration
        if self.in_progress == False:
            raise RequestNotSentError()
        m = await asyncio.wait_for(self.queue.get(), self.timeout)
        if self.finished:
            raise StopAsyncIteration
        if m["type"] == "command_status":
            if m["args"]["ok"] != True:
                self.finished = True
                raise RequestError(m["args"])
            else:
                self.finished = True
                raise StopAsyncIteration
        else:
            return m

    async def wait_success(self):
        async for m in self:
            pass
        


