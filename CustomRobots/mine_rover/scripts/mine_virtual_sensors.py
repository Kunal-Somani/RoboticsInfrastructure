#!/usr/bin/env python3
import math

import rclpy
from rclpy.node import Node
from std_msgs.msg import Float32
from nav_msgs.msg import Odometry


CRACK_LOCATIONS = [
    (-1.95,  0.0,  1.5),   # C1: west junction wall
    (-1.95, -8.0,  1.4),   # C2: south arm left wall
    ( 0.5,  23.8,  1.8),   # C3: north dead-end back wall
    (18.0,   1.95, 1.5),   # C4: east arm right wall
    ( 0.5,  -20.0, 3.45),  # C5: south arm ceiling
]
CRACK_DETECT_RADIUS = 3.0

CH4_POCKETS = [
    ( 1.0, -22.0, 1.0, 2.5),   # G1: south dead-end
    (-22.0,  0.0, 1.0, 2.5),   # G2: west dead-end
]

CO_POCKETS = [
    (22.0, 0.0, 1.0, 2.5),     # G3: east dead-end
]


class VirtualSensorsNode(Node):
    def __init__(self):
        super().__init__("mine_virtual_sensors")

        self.pub_ch4 = self.create_publisher(Float32, "/mine_rover/gas/ch4", 10)
        self.pub_co = self.create_publisher(Float32, "/mine_rover/gas/co", 10)
        self.pub_cracks = self.create_publisher(
            Float32, "/mine_rover/cracks/detected", 10
        )

        self.sub_odom = self.create_subscription(
            Odometry, "/odom", self.odom_callback, 10
        )

        # 5 Hz publish rate
        self.timer = self.create_timer(1.0 / 5.0, self.timer_callback)

        self.current_x = 0.0
        self.current_y = 0.0

    def odom_callback(self, msg: Odometry):
        self.current_x = msg.pose.pose.position.x
        self.current_y = msg.pose.pose.position.y

    def timer_callback(self):
        self.publish_gas()
        self.publish_cracks()

    def get_gas_concentration(self, pockets):
        max_concentration = 0.0
        for px, py, pz, pradius in pockets:
            distance = math.sqrt(
                (self.current_x - px) ** 2 + (self.current_y - py) ** 2
            )
            concentration = max(0.0, 1.0 - (distance / pradius))
            if concentration > max_concentration:
                max_concentration = concentration
        return max_concentration

    def publish_gas(self):
        ch4_msg = Float32()
        ch4_msg.data = self.get_gas_concentration(CH4_POCKETS)
        self.pub_ch4.publish(ch4_msg)

        co_msg = Float32()
        co_msg.data = self.get_gas_concentration(CO_POCKETS)
        self.pub_co.publish(co_msg)

    def publish_cracks(self):
        detected = 0.0
        for cx, cy, cz in CRACK_LOCATIONS:
            # 2D distance for robust detection (avoids Z-height failures)
            distance = math.sqrt(
                (self.current_x - cx) ** 2 + (self.current_y - cy) ** 2
            )
            if distance <= CRACK_DETECT_RADIUS:
                detected = 1.0
                break

        crack_msg = Float32()
        crack_msg.data = detected
        self.pub_cracks.publish(crack_msg)


def main(args=None):
    rclpy.init(args=args)
    node = VirtualSensorsNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
