from ag_motioncontrol import MotionController, RequestError

import asyncio
import argparse
from pprint import pprint
parser = argparse.ArgumentParser()

parser.add_argument("--transport", help="manual transport config. pass 'simulation' to use simulator")
parser.add_argument("--serial", help="board serial ID", default="robot_01")
args = parser.parse_args()

async def actiongraph_test():
    #creating API instance    
    api = MotionController(args.serial, manual_transport_config=args.transport, debug_log_level=10, force_reset=False)

    # reading notifications (status messages)
    async def notifications_reader():
        async with api.notifications() as n:
            async for msg in n:
                print("NOTIFICATION")
                pprint(msg)
    notifications_task = asyncio.create_task(notifications_reader())

    # awaiting for start
    
    await api.start()
    
    try:
        # this will run until we connect to robot and everything is ready for work
        print("\n\n\n##### Connecting to robot #####")
        from time import time
        ts = time()
        while True:
            ok = False
            async with api.request({"type": "connection_status_request" }) as req:
                async for m in req:
                    if m["args"]["is_online"] == True:
                        print("Done")
                        ok = True
            if ok:
                break
            await asyncio.sleep(1)
            if time() - ts > 30:
                raise Exception("No connection for 30 seconds, exiting")
        
        print("\n\n\n##### Test of parallel homing of 3 axes #####")

        async def homeAxis(axis):
            # homing of axis 1
            async with api.request({
                "args": {
                    "axis": axis,
                    # "speed": 10
                },
                "type": "do_homing"
            }) as req:
                await req.wait_success()
                print(f"Axis{axis} homing success")

        await asyncio.gather(
            homeAxis(1),
            homeAxis(2), 
            homeAxis(3)
        )

        # some movements in single request
        movements = [
            {
                "position": 10,
                "axis": 1,
            },
            {
                "position": 20,
                "axis": 1,
            },
            {
                "position": 10,
                "axis": 1,
                "label": "test marker",
            },
            {
                "position": 20,
                "axis": 1,
            },
            {
                "position": 10,
                "axis": 2,
            },
            {
                "position": 20,
                "axis": 2,
            },
            {
                "position": 5,
                "axis": 3,
            },
            {
                "position": 10,
                "axis": 3,
            }
            
        ]

        print("\n\n\n##### Test of movements batch #####")
        async with api.request({
            "args": {
                "movements": movements
            },
            "type": "enqueue_movements"
        }) as req:
            async for m in req:
                if m["type"] == "movement_finished":
                    print(f"Axis {m['args']['axis']} -> {m['args']['pos']}")
                    if "label" in m["args"]:
                        print(f'Movement with label "{m["args"]["label"]}" finished')
            print("Movements batch done")

        print("\n\n\n##### Test of movements batch with bad movement parameters #####")
        async with api.request({
            "args": {
                "movements": movements + [{
                    "position": 5,
                    "axis": 3,
                    "T": 0.0001
                }]
            },
            "type": "enqueue_movements"
        }) as req:
            try:
                async for m in req:
                    if m["type"] == "movement_finished":
                        print(f"Axis {m['args']['axis']} -> {m['args']['pos']}")
                print("Movements batch done")
            except RequestError as e:
                print("Movements batch error:", e)
            
        
        print("\n\n\n##### Test  movement cancelation #####")
        async def stopper(axis, delay):
            await asyncio.sleep(delay)
            print("stopping axis", axis)
            async with api.request({"type": "stop", "args": {"axis": axis}}) as req:
                await req.wait_success()
            print("axis ", axis, "is stopped")
        asyncio.create_task(stopper(1, 2.0))
        asyncio.create_task(stopper(2, 2.1))
        async with api.request({
            "args": {
                "movements": movements
            },
            "type": "enqueue_movements"
        }) as req:
            try:
                async for m in req:
                    if m["type"] == "movement_finished":
                        print(f"Axis {m['args']['axis']} -> {m['args']['pos']}")
                print("Movements batch done")
            except RequestError as e:
                print("Movements batch error:", e)


        print("\n\n\n##### Test of parallel axes control #####")
        await asyncio.gather(
            homeAxis(1),
            homeAxis(2), 
            homeAxis(3)
        )
        async def axisTask(axis, pos_incr,count):
            pos = pos_incr

            for i in range(count):
                async with api.request({
                    "args": {
                        "movements": [ { "position": pos, "axis": axis }]
                    },
                    "type": "enqueue_movements"
                }) as req:
                    await req.wait_success()
                    print(f"Axis{axis} movement {i+1}/{count} to {pos} is done")
                    pos += pos_incr

        await asyncio.gather(
            axisTask(1, 1.0, 5),
            axisTask(2, 1.5, 4), 
            axisTask(3, 2, 3)
        )
    except Exception as e:
        raise e
    finally:
        print("Shutting down")
        notifications_task.cancel()
        await api.stop()
        print("Done")
    

asyncio.run(actiongraph_test())


# import sys
# sys.settrace(print)
