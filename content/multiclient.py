from ag_motioncontrol import MotionController
import asyncio

board_1 = "robot_01"
board_2 = "robot_02"

async def actiongraph_test():

    api_1 = MotionController(board_1, manual_transport_config="simulation", debug_log_level=2, force_reset=False)
    api_2 = MotionController(board_2, manual_transport_config="simulation", debug_log_level=2, force_reset=False)
    await asyncio.gather(api_1.start(), api_2.start())
    
    async def notifications_reader(api):
        async with api.notifications() as n:
            async for msg in n:
                pass
    asyncio.create_task(notifications_reader(api_1))
    asyncio.create_task(notifications_reader(api_2))

    try:
        await asyncio.gather(api_1.wait_for_ready(), api_2.wait_for_ready())
        print("BOTH BOARDS ARE ONLINE")       

    except Exception as e:
        raise e
    finally:
        print("Shutting down")
        await asyncio.gather(api_1.stop(), api_2.stop())
        print("Done")
    

asyncio.run(actiongraph_test())
