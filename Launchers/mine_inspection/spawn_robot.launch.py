import os

from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():

    spawn_robot = Node(
        package="ros_gz_sim",
        executable="create",
        arguments=[
            "-name", "mine_rover",
            "-file", "/opt/jderobot/CustomRobots/mine_rover/models/mine_rover/model.sdf",
            "-x", "0",
            "-y", "-20",
            "-z", "0.2",
            "-Y", "1.5708",
        ],
        output="screen",
    )

    parameter_bridge = Node(
        package="ros_gz_bridge",
        executable="parameter_bridge",
        parameters=[{
            "config_file": "/opt/jderobot/CustomRobots/mine_rover/params/mine_rover.yaml"
        }],
        output="screen",
    )

    image_bridge = Node(
        package="ros_gz_image",
        executable="image_bridge",
        arguments=["/mine_rover/camera/image_raw"],
        output="screen",
    )

    ld = LaunchDescription()
    ld.add_action(spawn_robot)
    ld.add_action(parameter_bridge)
    ld.add_action(image_bridge)

    return ld
