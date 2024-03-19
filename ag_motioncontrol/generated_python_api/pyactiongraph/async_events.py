def ImportPythonZMQTransport():
    import asyncio
    import zmq
    import zmq.asyncio
    import lua_python_binding
    lua_scheduler = lua_python_binding.require("scheduler")

    class ZMQTransport:
        counter = 0
        ctx = zmq.asyncio.Context()
        def __init__(self) -> None:
            self.socket_in = None
            self.socket_out = None

        def open(self, **params):
            self.close()
        
            if 'in' not in params or 'out' not in params:
                return False
            try:
                if ZMQTransport.ctx is None:
                    ZMQTransport.ctx = zmq.asyncio.Context()
                self.socket_out = self.ctx.socket(zmq.PUB)
                self.socket_out.bind(params['out'])

                self.socket_in = self.ctx.socket(zmq.SUB)
                self.socket_in.connect(params['in'])
                self.socket_in.setsockopt_string(zmq.SUBSCRIBE, "")
            except Exception as e:
                self.close()
                return False
            else:
                ZMQTransport.counter += 1
                return True

        def readWithCallback(self, resolve, reject, timeout):
            async def wrapper():
                try:
                    if timeout == 0: #nonblock
                        res = await self.socket_in.recv(flags=zmq.NOBLOCK)
                        # print("received: ", res)
                        resolve(res)
                    elif timeout is None: # wait indefinitely
                        res = await self.socket_in.recv(flags=0)
                        # print("received: ", res)
                        resolve(res)
                    else:
                        res = await asyncio.wait_for(self.socket_in.recv(flags=0), timeout=timeout/1000)
                        # print("received: ", res)
                        resolve(res)
                except Exception as ex:
                    reject(type(ex).__name__, ex.args)
                finally:
                    lua_scheduler.runUntilNoActive()
            t = asyncio.create_task(wrapper())
            return lambda: t.cancel()

        def sendWithCallback(self, resolve, reject, data):
            async def wrapper():
                try:
                    res = await self.socket_out.send(data)
                    # print("sent: ", data)
                    resolve(res)
                except Exception as ex:
                    reject(type(ex).__name__, ex.args)
                finally:
                    lua_scheduler.runUntilNoActive()
            t = asyncio.create_task(wrapper())
            return lambda: t.cancel() 

        def close(self):
            if self.socket_in is not None or self.socket_out is not None:
                ZMQTransport.counter -= 1
            if self.socket_in:
                self.socket_in.close()
                self.socket_in = None
            if self.socket_out:
                self.socket_out.close()
                self.socket_out = None        
            # print("ZMQTransport.counter", ZMQTransport.counter)
            if ZMQTransport.counter == 0 and ZMQTransport.ctx is not None:
                # print("closing ZMQ context")
                ZMQTransport.ctx.destroy()
                ZMQTransport.ctx = None
    return ZMQTransport

def ImportPythonSerialTransport():
    import asyncio
    import serial_asyncio
    from serial.tools.list_ports import comports
    import lua_python_binding
    from .lua.utils import _toLua
    lua_scheduler = lua_python_binding.require("scheduler")

    class SerialTransport:

        def __init__(self) -> None:
            self.reader = None
            self.writer = None
        def available_connections(self):
            ret = []
            for p in comports():
                ret.append({"port":p.device, "description": p.description})
            return _toLua(ret)

        def openWithCallback(self, resolve, reject, params):
            async def wrapper():
                self.close()
                if 'port' not in params:
                    resolve(False)
                try:
                    self.reader, self.writer = await serial_asyncio.open_serial_connection(url=params['port'])
                except Exception as e:
                    print("Exception", e)
                    self.close()
                    resolve(False)
                else:
                    resolve(True)
            t = asyncio.create_task(wrapper())
            return lambda: t.cancel()

        def readWithCallback(self, resolve, reject, timeout):
            async def wrapper():
                try:
                    if timeout == 0: # need to return currently available bytes
                        res = await asyncio.wait_for(self.reader.read(512), timeout=0.001)
                        # print("received: ", res)
                        resolve(res)
                    elif timeout is None: # need to wait for any bytes and return as soon we have something
                        res = await self.reader.read(512)
                        # print("received: ", res)
                        resolve(res)
                    else:
                        res = await asyncio.wait_for(self.reader.read(512), timeout=timeout/1000)
                        # print("received: ", res)
                        resolve(res)

                except Exception as ex:
                    reject(type(ex).__name__, ex.args)
                finally:
                    lua_scheduler.runUntilNoActive()
            t = asyncio.create_task(wrapper())
            return lambda: t.cancel()

        def sendWithCallback(self, resolve, reject, data):
            async def wrapper():
                try:
                    self.writer.write(data)
                    await self.writer.drain()
                    # print("sent: ", data)
                    resolve(None)
                except Exception as ex:
                    reject(type(ex).__name__, ex.args)
                finally:
                    lua_scheduler.runUntilNoActive()
            t = asyncio.create_task(wrapper())
            return lambda: t.cancel() 

        def close(self):
            if self.writer:
                self.writer.close()
                self.writer = None
                self.reader = None
           
    return SerialTransport

def setup_async_events():
    from . import actiongraph_scheduler
    import asyncio
    import lua_python_binding
    lg = lua_python_binding.globals()
    lg.wrappedPythonSleep = actiongraph_scheduler.wrap_python_async(asyncio.sleep)
    lua_python_binding.execute("""
local scheduler = require'scheduler'
local utils = require'utils'
--utils.print("Replacing standard scheduler 'sleep' with python asyncio-based sleep" )
scheduler.sleep = function (s)
    if not s or s < 0 then
        s = 0
    end
    scheduler.waitExternalEvent(wrappedPythonSleep, s)
end
""")

    lg.ImportPythonZMQTransport = ImportPythonZMQTransport
    lua_python_binding.execute("""
local scheduler = require'scheduler'
local transport_wrapper = require'transport_wrapper'
local utils = require'utils'
local python = require'python'
--utils.print("Replacing standard ZMQ transport with python asyncio-based" )
transport_wrapper.transportFactory.zmq = function ()
    PythonZMQTransport = ImportPythonZMQTransport()
    return function()
        local ret = {}
        ret.t = PythonZMQTransport()
        function ret:availableConnections() return {} end
        function ret:open(conn) return self.t.open(conn) end
        function ret:close() return self.t.close() end
        function ret:readData(t) return scheduler.waitExternalEvent(self.t.readWithCallback, t) end
        function ret:sendData(data) return  scheduler.waitExternalEvent(self.t.sendWithCallback, python.asbytes(data)) end
        return ret
    end, true
end
""")

    lg.ImportPythonSerialTransport = ImportPythonSerialTransport
    lua_python_binding.execute("""
local scheduler = require'scheduler'
local transport_wrapper = require'transport_wrapper'
local utils = require'utils'
local python = require'python'
--utils.print("Replacing standard serial transport with python asyncio-based" )
transport_wrapper.transportFactory.serialport2 = function ()
    PythonSerialTransport = ImportPythonSerialTransport()
    return function()
        local ret = {}
        ret.t = PythonSerialTransport()
        function ret:availableConnections() return self.t.available_connections() end
        function ret:open(conn) return  scheduler.waitExternalEvent(self.t.openWithCallback, conn) end
        function ret:close() return self.t.close() end
        function ret:readData(t) return scheduler.waitExternalEvent(self.t.readWithCallback, t) end
        function ret:sendData(data) return  scheduler.waitExternalEvent(self.t.sendWithCallback, python.asbytes(data)) end
        return ret
    end, false
end
""")
