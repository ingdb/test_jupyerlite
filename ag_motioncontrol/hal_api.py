from enum import Enum
import struct
from .generated_python_api import API

class GPIO_DIRECTION(Enum):
    INPUT = 0
    OUTPUT = 1

class HAL_API:

    def __init__(self, generated_api: API) -> None:
        self.api = generated_api

    # simulator
    # async def configure_gpio(self, pin: int, mode: GPIO_DIRECTION) -> None:
    #     CONFIGURE_GPIO_HAL_REQUEST = 666
    #     data = struct.pack('<BB', pin, mode.value)
    #     await self.api.robot.hal_request(CONFIGURE_GPIO_HAL_REQUEST, data)

    async def configure_gpio(self, pin: int, mode: GPIO_DIRECTION) -> None:
        await self.api.robot.hal_request(0, struct.pack('<BBBB', 0, 1, pin, mode.value))

    

