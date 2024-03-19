from os import path
from .pyactiongraph.launcher import APIBase, RobotBase, IncomingEvent, OutgoingEvent, Parameter

class API(APIBase):

    def __init__(self,
            robot_serial_number=None,
            robot_manual_transport=None,
            robot_additional_simulator_rpc_connections=[],
            additional_client_rpc_connections=[],
            debug_logging=False,
            force_reset=False,
            simulation=False):
        super().__init__(
            path.join(path.dirname(path.abspath(__file__)), "src/main.yaml"),
            package_search_path=path.join(path.dirname(path.abspath(__file__)), "actiongraph_packages"), 
            manual_transport_configs = [
                (robot_serial_number, robot_manual_transport,),
            ],
            robot_serials_override = [
                ('robot', robot_serial_number,),
            ],
            additional_client_rpc_connections=additional_client_rpc_connections,
            additional_simulator_rpc_connections={
                'robot': robot_additional_simulator_rpc_connections,
            },
            debug_logging=debug_logging,
            force_reset=force_reset,
            simulation=simulation,
        )
        self.robot = None

    def start(self):
        super().start()
        self.robot = Robot_robot(self)


class Robot_robot(RobotBase):

    def __init__(self, api) -> None:
        super().__init__("robot", api)

        self.Graph_a0_positionReporter_starter_event = OutgoingEvent(self, "Graph.a0.positionReporter.starter.event")
        self.Graph_a0_positionReporter_stopper_event = OutgoingEvent(self, "Graph.a0.positionReporter.stopper.event")
        self.Graph_a0_startEventWaiter_event = OutgoingEvent(self, "Graph.a0.startEventWaiter.event")
        self.Graph_a0_homingEventWaiter_event = OutgoingEvent(self, "Graph.a0.homingEventWaiter.event")
        self.Graph_a0_breakEventWaiter_event = OutgoingEvent(self, "Graph.a0.breakEventWaiter.event")
        self.Graph_a1_positionReporter_starter_event = OutgoingEvent(self, "Graph.a1.positionReporter.starter.event")
        self.Graph_a1_positionReporter_stopper_event = OutgoingEvent(self, "Graph.a1.positionReporter.stopper.event")
        self.Graph_a1_startEventWaiter_event = OutgoingEvent(self, "Graph.a1.startEventWaiter.event")
        self.Graph_a1_homingEventWaiter_event = OutgoingEvent(self, "Graph.a1.homingEventWaiter.event")
        self.Graph_a1_breakEventWaiter_event = OutgoingEvent(self, "Graph.a1.breakEventWaiter.event")
        self.Graph_a2_positionReporter_starter_event = OutgoingEvent(self, "Graph.a2.positionReporter.starter.event")
        self.Graph_a2_positionReporter_stopper_event = OutgoingEvent(self, "Graph.a2.positionReporter.stopper.event")
        self.Graph_a2_startEventWaiter_event = OutgoingEvent(self, "Graph.a2.startEventWaiter.event")
        self.Graph_a2_homingEventWaiter_event = OutgoingEvent(self, "Graph.a2.homingEventWaiter.event")
        self.Graph_a2_breakEventWaiter_event = OutgoingEvent(self, "Graph.a2.breakEventWaiter.event")
        self.READ_GPIO_event = OutgoingEvent(self, "Graph.gpioControl.1.1.event")
        self.WRITE_GPIO_event = OutgoingEvent(self, "Graph.gpioControl.2.1.event")

        self.AxisPosEvent = IncomingEvent(self, "Graph.a0.positionReporter.event")
        self.Graph_a0_semifinishedReporter_event = IncomingEvent(self, "Graph.a0.semifinishedReporter.event")
        self.Graph_a0_allFinishedReporter_event = IncomingEvent(self, "Graph.a0.allFinishedReporter.event")
        self.Graph_a0_currentFinishedReporter_crtSender_event = IncomingEvent(self, "Graph.a0.currentFinishedReporter.crtSender.event")
        self.Graph_a0_mvErrorReporter_event = IncomingEvent(self, "Graph.a0.mvErrorReporter.event")
        self.Graph_a0_homingDoneReporter_event = IncomingEvent(self, "Graph.a0.homingDoneReporter.event")
        self.Graph_a1_positionReporter_event = IncomingEvent(self, "Graph.a1.positionReporter.event")
        self.Graph_a1_semifinishedReporter_event = IncomingEvent(self, "Graph.a1.semifinishedReporter.event")
        self.Graph_a1_allFinishedReporter_event = IncomingEvent(self, "Graph.a1.allFinishedReporter.event")
        self.Graph_a1_currentFinishedReporter_crtSender_event = IncomingEvent(self, "Graph.a1.currentFinishedReporter.crtSender.event")
        self.Graph_a1_mvErrorReporter_event = IncomingEvent(self, "Graph.a1.mvErrorReporter.event")
        self.Graph_a1_homingDoneReporter_event = IncomingEvent(self, "Graph.a1.homingDoneReporter.event")
        self.Graph_a2_positionReporter_event = IncomingEvent(self, "Graph.a2.positionReporter.event")
        self.Graph_a2_semifinishedReporter_event = IncomingEvent(self, "Graph.a2.semifinishedReporter.event")
        self.Graph_a2_allFinishedReporter_event = IncomingEvent(self, "Graph.a2.allFinishedReporter.event")
        self.Graph_a2_currentFinishedReporter_crtSender_event = IncomingEvent(self, "Graph.a2.currentFinishedReporter.crtSender.event")
        self.Graph_a2_mvErrorReporter_event = IncomingEvent(self, "Graph.a2.mvErrorReporter.event")
        self.Graph_a2_homingDoneReporter_event = IncomingEvent(self, "Graph.a2.homingDoneReporter.event")
        self.EMERGENCY_BREAK_TRIGGERED_event = IncomingEvent(self, "Graph.emergencyStopper.reporter.event")
        self.GPIO_DIN_VALUE_event = IncomingEvent(self, "Graph.gpioControl.1.3.rpt.event")

        self.Graph_a0_calibrater_actuatorZeroPos_param = Parameter(self, "Graph.a0.calibrater.actuatorZeroPos")
        self.Graph_a0_wrappedMovement_px_param = Parameter(self, "Graph.a0.wrappedMovement.px")
        self.Graph_a0_wrappedMovement_vx_param = Parameter(self, "Graph.a0.wrappedMovement.vx")
        self.Graph_a0_wrappedMovement_jerk_limit_param = Parameter(self, "Graph.a0.wrappedMovement.jerk_limit")
        self.Graph_a0_wrappedMovement_accel_limit_param = Parameter(self, "Graph.a0.wrappedMovement.accel_limit")
        self.Graph_a0_wrappedMovement_speed_limit_param = Parameter(self, "Graph.a0.wrappedMovement.speed_limit")
        self.Graph_a0_wrappedMovement_T_param = Parameter(self, "Graph.a0.wrappedMovement.T")
        self.Graph_a0_wrappedMovement_uniqueMovementId_param = Parameter(self, "Graph.a0.wrappedMovement.uniqueMovementId")
        self.Graph_a0_wrappedMovement_pos_at_start_param = Parameter(self, "Graph.a0.wrappedMovement.pos_at_start")
        self.Graph_a0_positionReporter_frequency_param = Parameter(self, "Graph.a0.positionReporter.frequency")
        self.Graph_a0_positionReporter_threshold_param = Parameter(self, "Graph.a0.positionReporter.threshold")
        self.Graph_a0_currentFinishedReporter_savedX_param = Parameter(self, "Graph.a0.currentFinishedReporter.savedX")
        self.Graph_a0_px_param = Parameter(self, "Graph.a0.px")
        self.Graph_a0_vx_param = Parameter(self, "Graph.a0.vx")
        self.Graph_a0_jerk_limit_param = Parameter(self, "Graph.a0.jerk_limit")
        self.Graph_a0_accel_limit_param = Parameter(self, "Graph.a0.accel_limit")
        self.Graph_a0_speed_limit_param = Parameter(self, "Graph.a0.speed_limit")
        self.Graph_a0_T_param = Parameter(self, "Graph.a0.T")
        self.Graph_a0_halMessage_param = Parameter(self, "Graph.a0.halMessage")
        self.Graph_a0_uniqueMovementId_param = Parameter(self, "Graph.a0.uniqueMovementId")
        self.Graph_a0_homingSpeed_param = Parameter(self, "Graph.a0.homingSpeed")
        self.Graph_a1_calibrater_actuatorZeroPos_param = Parameter(self, "Graph.a1.calibrater.actuatorZeroPos")
        self.Graph_a1_wrappedMovement_px_param = Parameter(self, "Graph.a1.wrappedMovement.px")
        self.Graph_a1_wrappedMovement_vx_param = Parameter(self, "Graph.a1.wrappedMovement.vx")
        self.Graph_a1_wrappedMovement_jerk_limit_param = Parameter(self, "Graph.a1.wrappedMovement.jerk_limit")
        self.Graph_a1_wrappedMovement_accel_limit_param = Parameter(self, "Graph.a1.wrappedMovement.accel_limit")
        self.Graph_a1_wrappedMovement_speed_limit_param = Parameter(self, "Graph.a1.wrappedMovement.speed_limit")
        self.Graph_a1_wrappedMovement_T_param = Parameter(self, "Graph.a1.wrappedMovement.T")
        self.Graph_a1_wrappedMovement_uniqueMovementId_param = Parameter(self, "Graph.a1.wrappedMovement.uniqueMovementId")
        self.Graph_a1_wrappedMovement_pos_at_start_param = Parameter(self, "Graph.a1.wrappedMovement.pos_at_start")
        self.Graph_a1_positionReporter_frequency_param = Parameter(self, "Graph.a1.positionReporter.frequency")
        self.Graph_a1_positionReporter_threshold_param = Parameter(self, "Graph.a1.positionReporter.threshold")
        self.Graph_a1_currentFinishedReporter_savedX_param = Parameter(self, "Graph.a1.currentFinishedReporter.savedX")
        self.Graph_a1_px_param = Parameter(self, "Graph.a1.px")
        self.Graph_a1_vx_param = Parameter(self, "Graph.a1.vx")
        self.Graph_a1_jerk_limit_param = Parameter(self, "Graph.a1.jerk_limit")
        self.Graph_a1_accel_limit_param = Parameter(self, "Graph.a1.accel_limit")
        self.Graph_a1_speed_limit_param = Parameter(self, "Graph.a1.speed_limit")
        self.Graph_a1_T_param = Parameter(self, "Graph.a1.T")
        self.Graph_a1_halMessage_param = Parameter(self, "Graph.a1.halMessage")
        self.Graph_a1_uniqueMovementId_param = Parameter(self, "Graph.a1.uniqueMovementId")
        self.Graph_a1_homingSpeed_param = Parameter(self, "Graph.a1.homingSpeed")
        self.Graph_a2_calibrater_actuatorZeroPos_param = Parameter(self, "Graph.a2.calibrater.actuatorZeroPos")
        self.Graph_a2_wrappedMovement_px_param = Parameter(self, "Graph.a2.wrappedMovement.px")
        self.Graph_a2_wrappedMovement_vx_param = Parameter(self, "Graph.a2.wrappedMovement.vx")
        self.Graph_a2_wrappedMovement_jerk_limit_param = Parameter(self, "Graph.a2.wrappedMovement.jerk_limit")
        self.Graph_a2_wrappedMovement_accel_limit_param = Parameter(self, "Graph.a2.wrappedMovement.accel_limit")
        self.Graph_a2_wrappedMovement_speed_limit_param = Parameter(self, "Graph.a2.wrappedMovement.speed_limit")
        self.Graph_a2_wrappedMovement_T_param = Parameter(self, "Graph.a2.wrappedMovement.T")
        self.Graph_a2_wrappedMovement_uniqueMovementId_param = Parameter(self, "Graph.a2.wrappedMovement.uniqueMovementId")
        self.Graph_a2_wrappedMovement_pos_at_start_param = Parameter(self, "Graph.a2.wrappedMovement.pos_at_start")
        self.Graph_a2_positionReporter_frequency_param = Parameter(self, "Graph.a2.positionReporter.frequency")
        self.Graph_a2_positionReporter_threshold_param = Parameter(self, "Graph.a2.positionReporter.threshold")
        self.Graph_a2_currentFinishedReporter_savedX_param = Parameter(self, "Graph.a2.currentFinishedReporter.savedX")
        self.Graph_a2_px_param = Parameter(self, "Graph.a2.px")
        self.Graph_a2_vx_param = Parameter(self, "Graph.a2.vx")
        self.Graph_a2_jerk_limit_param = Parameter(self, "Graph.a2.jerk_limit")
        self.Graph_a2_accel_limit_param = Parameter(self, "Graph.a2.accel_limit")
        self.Graph_a2_speed_limit_param = Parameter(self, "Graph.a2.speed_limit")
        self.Graph_a2_T_param = Parameter(self, "Graph.a2.T")
        self.Graph_a2_halMessage_param = Parameter(self, "Graph.a2.halMessage")
        self.Graph_a2_uniqueMovementId_param = Parameter(self, "Graph.a2.uniqueMovementId")
        self.Graph_a2_homingSpeed_param = Parameter(self, "Graph.a2.homingSpeed")
        self.Graph_gpioControl_gpioValueToWrite_param = Parameter(self, "Graph.gpioControl.gpioValueToWrite")
        self.Hardware_Motor0_user_defined_scale_param = Parameter(self, "Hardware.Motor0.user_defined_scale")
        self.Hardware_Motor1_user_defined_scale_param = Parameter(self, "Hardware.Motor1.user_defined_scale")
        self.Hardware_Motor2_user_defined_scale_param = Parameter(self, "Hardware.Motor2.user_defined_scale")
        self.Hardware_GPIOControlModule_hal_id_param = Parameter(self, "Hardware.GPIOControlModule.hal_id")


