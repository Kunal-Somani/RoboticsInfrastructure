# Launchers/mine_inspection.launch.py
import os

from ament_index_python.packages import get_package_share_directory

from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription, SetEnvironmentVariable
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch_ros.actions import Node


MINE_MODEL_PATHS = ":".join([
    "/opt/jderobot/CustomRobots/mine_inspection/models/tiles",
    "/opt/jderobot/CustomRobots/mine_inspection/models/props",
    "/opt/jderobot/CustomRobots/mine_inspection/models",
    "/opt/jderobot/CustomRobots/mine_rover/models",
])


def generate_launch_description():
    ros_gz_sim = get_package_share_directory("ros_gz_sim")

    world_file_name = "mine_inspection.world"
    worlds_dir = "/opt/jderobot/Scenes"
    world_path = os.path.join(worlds_dir, world_file_name)

    set_gz_model_path = SetEnvironmentVariable(
        name="GZ_SIM_RESOURCE_PATH",
        value=MINE_MODEL_PATHS + ":" + os.environ.get("GZ_SIM_RESOURCE_PATH", ""),
    )

    gazebo_server = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(ros_gz_sim, "launch", "gz_sim.launch.py")
        ),
        launch_arguments={
            "gz_args": ["-s -v4 ", world_path],
            "on_exit_shutdown": "true",
        }.items(),
    )

    world_entity_cmd = Node(
        package="ros_gz_sim",
        executable="create",
        arguments=["-name", "world", "-file", world_path],
        output="screen",
    )

    spawn_robot = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            "/opt/jderobot/Launchers/mine_inspection/spawn_robot.launch.py"
        )
    )

    gz_ros2_bridge = Node(
        package="ros_gz_bridge",
        executable="parameter_bridge",
        arguments=[
            "/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock",
        ],
        output="screen",
    )

    ld = LaunchDescription()
    ld.add_action(set_gz_model_path)
    ld.add_action(gazebo_server)
    ld.add_action(world_entity_cmd)
    ld.add_action(spawn_robot)
    ld.add_action(gz_ros2_bridge)

    return ld