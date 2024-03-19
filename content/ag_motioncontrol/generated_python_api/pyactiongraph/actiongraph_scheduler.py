import asyncio
import lua_python_binding

lua_scheduler = lua_python_binding.require("scheduler")

if isinstance(lua_scheduler, tuple):
    lua_scheduler = lua_scheduler[0]

async def actiongraph_scheduler_task():
    try:
        finish_event = asyncio.Event()
        lua_scheduler.finished_callback = lambda: finish_event.set()
        if lua_scheduler.runUntilNoActive():
            await finish_event.wait()
       
        print("Actiongraph scheduler job finished")
    except asyncio.CancelledError as e:
        # print(e)
        # lua_scheduler.print_running()
        raise e
    finally:
        transport_wrapper = lua_python_binding.require("transport_wrapper")
        if isinstance(transport_wrapper, tuple):
            transport_wrapper = transport_wrapper[0]
        transport_wrapper.shutdown_all()


def run(*coros):
    async def main(*c):
        await asyncio.gather(actiongraph_scheduler_task(), *c)
    asyncio.run(main(*coros))

def wrap_python_async(coro):
    def wrapped(callback_resolve, callback_reject, *args):
        async def wrapper(to_call, resolve, reject, *arguments):
            try:
                ret = await to_call(*arguments)
                if isinstance(ret, tuple):
                    resolve(*ret)
                else:
                    resolve(ret)
            except Exception as ex:
                reject(type(ex).__name__, ex.args)
            finally:
                lua_scheduler.runUntilNoActive()
        task = asyncio.create_task(wrapper(coro, callback_resolve, callback_reject, *args))
        return lambda: task.cancel()
    return wrapped

lua_async_call_helper = lua_python_binding.eval("""
            function(f, clb)
                local scheduler = require'scheduler'

                scheduler.addTask(function()
                    f()
                    clb()                    
                end)                                                    
            end
        """)

async def call_lua_async(lua_coro):
    evt = asyncio.Event()
    lua_async_call_helper(lua_coro, lambda: evt.set())
    await evt.wait()
