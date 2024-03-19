import asyncio
import zmq
import zmq.asyncio
from aiohttp import web
import aiohttp.web_exceptions

class AsyncZMQWebsocketsbBridge:
    def __init__(self, pub_zmq_address, sub_zmq_address, http_port=8080, static_content_dirs=[], debug=False):
        self.pub_zmq_address = pub_zmq_address
        self.sub_zmq_address = sub_zmq_address
        self.static_content_dirs = static_content_dirs
        self.websockets = []
        self.ctx = zmq.asyncio.Context()
        self.web_runner = None
        self.debug = debug
        self.http_port = http_port

    async def zmq_subscriber(self):
        self.sub_socket = self.ctx.socket(zmq.SUB)
        self.sub_socket.connect(self.sub_zmq_address)
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, '')
        while True:
            msg = await self.sub_socket.recv_string()
            await self.broadcast(msg)

    async def zmq_publisher(self):
        # This method now just sets up the publisher socket.
        # It doesn't need to run a loop since we're not using it to periodically send messages.
        self.pub_socket = self.ctx.socket(zmq.PUB)
        self.pub_socket.bind(self.pub_zmq_address)

    async def websocket_handler(self, request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        self.websockets.append(ws)
        try:
            async for msg in ws:
                if msg.type == aiohttp.WSMsgType.TEXT:
                    await self.pub_socket.send_string(msg.data)
                elif msg.type == aiohttp.WSMsgType.ERROR:
                    print('ws connection closed with exception %s' % ws.exception())
        finally:
            self.websockets.remove(ws)

        return ws

    async def broadcast(self, message):
        if(self.debug):
            print(f"Broadcasting {message}")
        disconnected_ws = []
        for ws in self.websockets:
            try:
                await ws.send_str(message)
            except ConnectionResetError:
                disconnected_ws.append(ws)
        for ws in disconnected_ws:
            self.websockets.remove(ws)

    async def start(self):
        # ZMQ
        asyncio.create_task(self.zmq_subscriber())
        asyncio.create_task(self.zmq_publisher())  # Start it but don't wait for it
        
        # Web server
        app = web.Application()
        for dir_path in self.static_content_dirs:
            app.router.add_static('/', dir_path, name='static', show_index=True)
        app.router.add_route('GET', '/ws', self.websocket_handler)
        
        self.web_runner = web.AppRunner(app)
        await self.web_runner.setup()
        self.site = web.TCPSite(self.web_runner, 'localhost', self.http_port)
        await self.site.start()
        if self.debug:
            print(f"ZMQ WS Bridge server ('{self.pub_zmq_address}' '{self.sub_zmq_address}') <=> http://localhost:{self.http_port} started")

    async def stop(self):
        # Close WebSocket connections
        for ws in self.websockets:
            await ws.close()

        # Shutdown web server
        if self.site:
            await self.site.stop()
        if self.web_runner:
            await self.web_runner.cleanup()

        # Close ZeroMQ connections
        if hasattr(self, 'pub_socket'):
            self.pub_socket.close()
        if hasattr(self, 'sub_socket'):
            self.sub_socket.close()

        # Terminate the ZMQ context
        self.ctx.term()
