from ag_motioncontrol import MotionController

import asyncio
import argparse
from pprint import pprint
import itertools

parser = argparse.ArgumentParser()

parser.add_argument("--transport", help="manual transport config. pass 'simulation' to use simulator")
parser.add_argument("--serial", help="board serial ID", default="robot_01")
args = parser.parse_args()

async def actiongraph_test():
    #creating API instance    
    ide_client_conn_port = 20000
    ide_sim_conn_port = 30000
    ide_host = "127.0.0.1"

    api = MotionController(args.serial, manual_transport_config=args.transport, force_reset=False, 
                        debug_log_level=0,
                        additional_client_rpc_connections=[f'zmq in=tcp://{ide_host}:{ide_client_conn_port + 1} out=tcp://0.0.0.0:{ide_client_conn_port}'],
                        additional_simulator_rpc_connections=[f'zmq in=tcp://{ide_host}:{ide_sim_conn_port + 1} out=tcp://0.0.0.0:{ide_sim_conn_port}']
    )
    
    test_movements = [
        {
            "position": 0.1,
            "axis": 1,
        },
        {
            "position": 0.15,
            "axis": 2,
        },
        {
            "position": 0.05,
            "axis": 1,
        },
        {
            "position": 0.05,
            "axis": 2,
        }  
    ]
    await api.start()
    try:
        await api.wait_for_ready()
        for i in range(1, 3):
            await api.set_pos_feedback_frequency(i, 50)

        scale_factors = [-1, 1, -0.5, 0.5]
        home_positions = [0, 0.2, -0.2]

        await asyncio.gather(*[api.do_homing(i, speed=0.001) for i in range(1, 3)])
        # await asyncio.sleep(1000)

        for scale_factor, home_position in itertools.product(scale_factors, home_positions):
            await asyncio.gather(*[api.set_coordinate_transform(i, scale_factor, home_position, triggered_homing_speed=0.001) for i in range(1, 3)])
            print(f"Axis scale: {scale_factor}, home sensor position: {home_position}")
            await asyncio.sleep(2)
            for  _ in range(2):
                await api.execute_movements(test_movements, max_acceleration=0.5)

            for i in range(1, 3):
                print(f"Axes {i} position: {api.get_axis_pos(i)}")
     
    finally:
        await api.stop()
    

asyncio.run(actiongraph_test())
