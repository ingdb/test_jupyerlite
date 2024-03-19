from ag_motioncontrol import MotionController

import asyncio
import argparse
from pprint import pprint
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
    

    await api.start()
    try:
        await api.wait_for_ready()
        for i in range(3):
            await api.set_pos_feedback_frequency(i+1, 50)

        for  _ in range(2):
            await api.execute_movements([
                [
                    {
                        "position": 0.1,
                        "axis": 1,
                    },
                    {
                        "position": 0.1,
                        "axis": 2,
                    }
                ],
                {
                        "position": 0.15,
                        "axis": 1,
                },
                [
                    {
                        "position": 0.05,
                        "axis": 1,
                    },
                    {
                        "position": 0.05,
                        "axis": 2,
                    }
                ],
                {
                        "position": 0.15,
                        "axis": 3,
                },
                [
                    {
                        "position": 0.0,
                        "axis": 1,
                    },
                    {
                        "position": 0.0,
                        "axis": 2,
                    },
                    {
                        "position": 0.0,
                        "axis": 3,
                    }
                ],
            ], max_acceleration=0.5)
        for i in range(1, 4):
            print(f"Axes {i} position: {api.get_axis_pos(i)}")

        # explicit T value for parallel movements
        await api.execute_movements([
            [
                {
                    "position": 0.5,
                    "axis": 1
                },
                {
                    "position": 0.5,
                    "axis": 2,
                    "T": 7
                },
                {
                    "position": 0.5,
                    "axis": 3
                }
            ],
        ], max_acceleration=0.5, max_speed=1)
        for i in range(1, 4):
            print(f"Final axes {i} position: {api.get_axis_pos(i)}")
    finally:
        await api.stop()
    

asyncio.run(actiongraph_test())
