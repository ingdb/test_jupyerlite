from ..lua import setup_lua_interpreter, add_lua_search_paths

import asyncio
import sys
from os import path
setup_lua_interpreter()
add_lua_search_paths([path.dirname(path.abspath(__file__)), path.join(path.dirname(path.abspath(__file__)),  "..", "actiongraph")])

from ..async_events import setup_async_events
setup_async_events()

from ..actiongraph_scheduler import actiongraph_scheduler_task, lua_scheduler, call_lua_async

import lua_python_binding
lg = lua_python_binding.globals()
lg.DO_NOT_RUN_AG_LOOP = True

from ..lua.utils import _fromLua, _toLua

_utils = lua_python_binding.require("utils")
if isinstance(_utils, tuple):
    _utils = _utils[0]

stderrPrintFunction = lambda s: print(s, file=sys.stderr, end = '')
def stderrPrinter(data):
    stderrPrintFunction(data)

_utils.printFunction = stderrPrinter
_Vector = lua_python_binding.require("vector")
if isinstance(_Vector, tuple):
    _Vector = _Vector[0]

lua_cli_module = lua_python_binding.require("cli")
if isinstance(lua_cli_module, tuple):
    lua_cli_module = lua_cli_module[0]
class APIBase:
    ag_lua_scheduler_task = None
    ag_lua_scheduler_task_stopper = None
    simulator_port_index = 0
    simulator_port_range_start = 10000
    running_api_instances = set()

    def __init__(self, main_file_path, debug_logging=False, force_reset=False, robot_serials_override=None, manual_transport_configs=None, simulation=False, package_search_path=None, additional_client_rpc_connections=[], additional_simulator_rpc_connections={}):
        self.debug_logging = debug_logging
        self.force_reset = force_reset
        self.main_task_stopper = None
        self.main_file_path = main_file_path
        self.robot_serials_override = robot_serials_override
        self.manual_transport_configs = manual_transport_configs
        self.simulation = simulation
        self.package_search_path = package_search_path    
        self.robots = dict()    
        self._simulator_closers = []
        self._context_creator = None
        self.in_queue = asyncio.Queue()
        self.out_queue = asyncio.Queue()
        self.lua_actiongraph_client = None
        self.additional_client_rpc_connections = additional_client_rpc_connections
        self.additional_simulator_rpc_connections = additional_simulator_rpc_connections
        async_rpc_interface_creator = lua_python_binding.eval("""
            function(sendPythonRPCMsgWithCallback, waitPythonRPCMsgWithCallback)
                local utils = require'utils'
                local scheduler = require'scheduler'
                --utils.print("Replacing standard stdio RPC with high-level python queues")
                return 
                    function (data) return scheduler.waitExternalEvent(sendPythonRPCMsgWithCallback, data) end,
                    function () return {scheduler.waitExternalEvent(waitPythonRPCMsgWithCallback)} end
            end
        """)
        def waitPythonRPCMsgWithCallback(resolve, reject):
            async def wrapper():
                try:
                    # print("WAITING EVENT FROM PYTHON")
                    res = await self.in_queue.get()
                    # print("RECEIVED MSG FROM PYTHON", res)
                    resolve(_toLua(res))
                except Exception as ex:
                    reject(type(ex).__name__, ex.args)
                finally:
                    lua_scheduler.runUntilNoActive()
            t = asyncio.create_task(wrapper())
            return lambda: t.cancel()

        def sendPythonRPCMsgWithCallback(resolve, reject, data):
            async def wrapper():
                try:
                    await self.out_queue.put(_fromLua(data))
                    # print("SENT MSG FROM AG", _fromLua(data))
                    resolve()
                except Exception as ex:
                    reject(type(ex).__name__, ex.args)
                finally:
                    lua_scheduler.runUntilNoActive()
            t = asyncio.create_task(wrapper())
            return lambda: t.cancel()
        self.lua_out_rpc_funct, self.lua_in_rpc_funct = async_rpc_interface_creator(sendPythonRPCMsgWithCallback, waitPythonRPCMsgWithCallback)

    async def shutdown_simulators(self):
        await asyncio.gather(* self._simulator_closers)
        self._simulator_closers = []

    def start(self):
        if self.debug_logging:
            stderr_printer = lambda s: print(s, file=sys.stderr, end = '')
            simulator_log_printer = lambda s: print(s+'\n', file=sys.stderr,end = '')
        else:
            stderr_printer = lambda s: None
            simulator_log_printer = lambda s: None
        
        debug_log_level=self.debug_logging if self.debug_logging else 0

        if debug_log_level > 0:
            # print(_utils.info_level)
            _utils.info_level = debug_log_level
            # print(_utils.info_level)

        args = {}
        if self.robot_serials_override:
            args['serial_ids'] = []
            for robot_id, serial in self.robot_serials_override:
                if robot_id and serial:
                    args['serial_ids'].append([robot_id, serial])
        if self.force_reset == True:
            args['force'] = True
        if self.manual_transport_configs is not None:
            args['fixed_connections'] = []
            for serial, conf in self.manual_transport_configs:
                if conf and serial:
                    args['fixed_connections'].append([serial, conf])
        args['input'] = self.main_file_path
        args['ACTIONGRAPH_PACKAGE_SEARCH_PATH'] = self.package_search_path

        global stderrPrintFunction # FIXME
        stderrPrintFunction = stderr_printer
        args['ag_rpc_transport_config'] = [{
            "rpcSendFunction": self.lua_out_rpc_funct,
            "rpcReceiveFunction": self.lua_in_rpc_funct
        }, *self.additional_client_rpc_connections]

        self.lua_actiongraph_client = lua_cli_module.CreateActionGraphClient(_toLua(args))

        # actiongraph/interpreter/user_script_robot_api.lua
        self._context_creator = self.lua_actiongraph_client.CreateScriptingContext

        if self.simulation == True:
            from ..simulator import Simulator

            robots_info = _fromLua(self.lua_actiongraph_client.GetRobotsSerialInfo())
            for robot_id, robot_info in robots_info.items():
                serial = robot_info["Serial"]
                self.lua_actiongraph_client.ChangeRobotTransport(robot_id, f"zmq in=tcp://127.0.0.1:{APIBase.simulator_port_range_start+APIBase.simulator_port_index} out=tcp://127.0.0.1:{APIBase.simulator_port_range_start+1+APIBase.simulator_port_index}")
                sim = Simulator()
                asyncio.create_task(sim.start(
                        serial=serial,
                        transport = f"zmq in=tcp://127.0.0.1:{APIBase.simulator_port_range_start+1+APIBase.simulator_port_index} out=tcp://127.0.0.1:{APIBase.simulator_port_range_start+APIBase.simulator_port_index}",
                        manifest_path= path.join(path.dirname(path.abspath(self.main_file_path)), "simulation","manifest.yaml"),
                        log_printer=simulator_log_printer,
                        additional_rpc_connections = self.additional_simulator_rpc_connections[robot_id] if robot_id in self.additional_simulator_rpc_connections else []
                    ))
                APIBase.simulator_port_index += 2
                async def stopper(sim, robot_id, serial):
                    print(f"Shutting down simulator {robot_id}({serial})")
                    await sim.stop()
                    print(f"Shutted down simulator {robot_id}({serial})")
                self._simulator_closers.append(stopper(sim, robot_id, serial))
        
        APIBase.running_api_instances.add(self)
        
        if APIBase.ag_lua_scheduler_task is None:
            async def ticker():
                try:
                    await actiongraph_scheduler_task()
                except Exception as e:
                    raise e
                    
            APIBase.ag_lua_scheduler_task = asyncio.create_task(ticker())
            async def stopper():
                # print("stopper called")
                if not APIBase.ag_lua_scheduler_task.done():
                    toc = APIBase.ag_lua_scheduler_task
                    APIBase.ag_lua_scheduler_task = None
                    toc.cancel()
                try:
                    await toc
                except asyncio.CancelledError:
                    pass
                except Exception as e:
                    print("Exited actiongraph main loop with exception: ", e)
                    raise e
                
            APIBase.ag_lua_scheduler_task_stopper = stopper


    async def stop(self):
        await self.shutdown_simulators()
        if self.lua_actiongraph_client is not None:
            await call_lua_async(self.lua_actiongraph_client.Shutdown)
            self.lua_actiongraph_client = None
        APIBase.running_api_instances.remove(self)
        if len(APIBase.running_api_instances) == 0:
            if APIBase.ag_lua_scheduler_task_stopper:
                await APIBase.ag_lua_scheduler_task_stopper()
                APIBase.ag_lua_scheduler_task_stopper = None


    async def wait_robots_ready(self):
        await asyncio.gather(
            *[r.wait_for_ready() for _, r in self.robots.items()]
        )
    async def __aenter__(self):
        self.start()
        return self
    async def __aexit__(self, *args):
        await self.stop()

    def send_event(self):
        pass

    def context_creator(self, id):
        return self._context_creator(id)
    

    async def receive_rpc_msg(self):
        r = await self.out_queue.get()
        return r
        

    async def send_rpc_msg(self, m):
        await self.in_queue.put(m)

class OutgoingEvent:
    def __init__(self, robot, ag_path) -> None:
        self.robot = robot
        self.ag_path = ag_path
        self.ok = False
        self.error = None
    async def send(self):
        event = asyncio.Event()
        self.ok = False
        self.error = None
        def resolve():
            self.ok = True
            event.set()
        def reject(err):
            self.error = err
            event.set()
        lua_scheduler.callAsyncFunctionWithCallback(self.robot.lua_ag_context.SendEvent, resolve, reject, self.ag_path)
        await event.wait()
        if not self.ok:
            raise Exception(self.error)

class IncomingEvent:
    def __init__(self, robot, ag_path):
        self.robot = robot
        self.ag_path = ag_path
        self.handlers = []
        self.event = asyncio.Event()
        self.last_data = None
        def handler(**args):
            self.last_data = _fromLua(args)
            self.event.set()
            for h in self.handlers: h(args)
        robot.lua_ag_context.EventHandler(self.ag_path, handler)

    def __await__(self):
        async def waiter():
            self.event.clear()
            await self.event.wait()
            return self.last_data
        return waiter().__await__()

    def add_handler(self, handler):
        self.handlers.append(handler)

class ParamReceivingFailed(Exception):
    pass
class Parameter:
    def __init__(self, robot, ag_path):
        self.robot = robot
        self.ag_path = ag_path
        self.result = None
        self.error = None
    async def set(self, value):
        event = asyncio.Event()
        self.result = None
        self.error = None
        def clb(*posRes, **res):
            if len(posRes) == 1:
                self.result = posRes[0]
            event.set()
        def reject(err):
            self.error = err
            event.set()
        if isinstance(value, list) and len(value) == 3:
            value = _Vector(*value)
        else:
            value = _toLua(value)

        lua_scheduler.callAsyncFunctionWithCallback(self.robot.lua_ag_context.SetParam, clb, reject, self.ag_path, value)
        await event.wait()
        if self.error is not None:
            raise Exception(self.error)
        return self.result
    async def get(self):
        self.result = None
        self.error = None
        event = asyncio.Event()
        def clb(*posRes, **res):
            if len(posRes) == 0:
                raise ParamReceivingFailed
            elif len(posRes) == 1:
                self.result = posRes[0]
            elif len(res) > 0:
                self.result = [res['x'], res['y'], res['z']]
            else:
                raise NotImplementedError
            event.set()
        def reject(err):
            self.error = err
            event.set()
        lua_scheduler.callAsyncFunctionWithCallback(self.robot.lua_ag_context.GetParam, clb, reject, self.ag_path)

        await event.wait()
        return self.result

class HALRequestError(Exception):
    pass

class RobotBase:
    def __init__(self, id, api) -> None:
        self.id = id
        self.lua_ag_context = api.context_creator(id)

        self.readyEvent = asyncio.Event()
        if self.lua_ag_context.IsRobotReady():
            self.readyEvent.set()
        else:
            self.readyEvent.clear()
        self.lua_ag_context.ReadyHandler(lambda: self.readyEvent.set())
        self.lua_ag_context.DisconnectHandler(lambda: self.readyEvent.clear())
        api.robots[id] = self

    async def wait_for_ready(self):
        if not self.lua_ag_context.IsRobotReady():
            self.readyEvent.clear()
            await self.readyEvent.wait()
    
    async def send_message_to_hal(self, msg_id:int, msg:str):
        # TODO
        event = asyncio.Event()
        def clb(*posRes, **res):
            event.set()
        def reject(err):
            event.set()
        lua_scheduler.callAsyncFunctionWithCallback(self.lua_ag_context.SendMessageToHal, clb, reject, msg_id, msg)
        await event.wait()

    async def hal_request(self, request_type, msg):
        event = asyncio.Event()
        res = None
        exc = None
        def clb(*args):
            nonlocal res
            if len(args) == 1:
                res = args[0]
            event.set()
        def reject(err):
            nonlocal exc
            exc = HALRequestError(err)
            event.set()
        lua_scheduler.callAsyncFunctionWithCallback(self.lua_ag_context.HALRequest, clb, reject, request_type, msg)
        await event.wait()
        if exc is not None:
            raise exc
        if res is None:
            raise HALRequestError("HAL request timeout")
        if  res.result != 0:
            raise HALRequestError(f"HAL request failed with error code {res.result}")
        return res.data[:res.size]

