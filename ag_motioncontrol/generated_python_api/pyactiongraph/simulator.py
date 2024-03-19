import json
import asyncio
import subprocess
from os import path
import platform
import os

class Simulator:
    def __init__(self) -> None:
        self.proc = None
        self.log_printer = lambda s: None



            
    async def start(self, serial=None, manifest_path=None, transport=None, log_printer=lambda s: None, additional_rpc_connections=[]):
        self.log_printer = log_printer
        args =   [
            "-p","transport",transport,
            "-s", serial,
            "-m", manifest_path
        ]
        for additonal_rpc in additional_rpc_connections:
            args.append("--ag_rpc_transport_config")
            args.append(additonal_rpc)

        this_path = path.dirname(path.abspath(__file__))
        pl = platform.system()
        if pl == "Darwin":
            if platform.machine() == "x86_64" or platform.machine() == "AMD64":
                exe_prefix = "macos_x86/lua_interpreter"
            else:
                exe_prefix = "macos/lua_interpreter"
        elif pl == "Windows":
            exe_prefix = "windows\\lua_interpreter.exe"
        elif pl == "Linux":
            if platform.machine() == "x86_64" or platform.machine() == "AMD64":
                exe_prefix = 'linux-x86_64/lua_interpreter'
            else:
                exe_prefix = 'linux-aarch64/lua_interpreter'
        data = {
            "cmd": path.join(this_path, "lua", "lua_interpreter", exe_prefix),
            "args": [
                path.join(this_path, "simulator", "simulator.lua"),
                *args
            ],
            "cwd": path.dirname(path.join(this_path, "lua", "lua_interpreter", exe_prefix)),
            "env": {
                "ACTIONGRAPH_ADDITIONAL_PATHS": path.join(this_path, "actiongraph")
            }
        }
        sub_env = os.environ.copy()
        for k in data["env"]:
            sub_env[k] = data["env"][k]

        self.log_printer(f"PROCESS STARTING: {data}")

        def run_in_thread():
            try:
                with subprocess.Popen([data["cmd"], *data["args"]], stderr=subprocess.PIPE, text=False, bufsize=0 ,env=sub_env,cwd=data["cwd"]) as process:
                    self.proc = process
                    while True:
                        line = process.stderr.readline()
                        if not line:
                            break
                        # print(line)
                        self.log_printer(f"Simulator log: {line.decode('utf-8').strip()}")
                    process.wait()
                    self.proc = None
                    return process.returncode
            except Exception as e:
                print(e)
                raise e

        asyncio.create_task(asyncio.to_thread(run_in_thread))


    async def stop(self):
        if self.proc is not None and self.proc.poll() is None:
            self.proc.terminate()  # Send a SIGTERM
            await asyncio.to_thread(self.proc.wait)  # W
            self.proc = None
