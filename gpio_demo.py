from ag_motioncontrol import MotionController
from ag_motioncontrol.hal_api import GPIO_DIRECTION
import asyncio
import argparse
from pprint import pprint
parser = argparse.ArgumentParser()

parser.add_argument("--transport", help="manual transport config. pass 'simulation' to use simulator")
parser.add_argument("--serial", help="board serial ID", default="robot_01")
args = parser.parse_args()

async def actiongraph_test():
    for i in range(10):
        #creating API instance    
        api = MotionController(args.serial, manual_transport_config=args.transport, force_reset=False, debug_log_level=0)

        await api.start()
        await api.wait_for_ready()

        await api.HAL.configure_gpio(10, GPIO_DIRECTION.INPUT)
        await api.HAL.configure_gpio(20, GPIO_DIRECTION.OUTPUT)

        # pprint(await api.generated_api.robot.hal_request(128, "101010"))
        # pprint(await api.generated_api.robot.hal_request(129, "020202FF"))
        
        pprint(await api.read_gpio(32))
        await api.write_gpio(22, 1)
        await api.stop()
    

asyncio.run(actiongraph_test())
