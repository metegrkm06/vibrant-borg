import socket
import threading
import time

DISCOVERY_PORT = 5005
VIDEO_TCP_PORT = 5003
VIDEO_UDP_PORT = 5004

class NetworkManager:
    def __init__(self, pc_name="BonayPC"):
        self.pc_name = pc_name
        self.running = False
        self.sock = None
        self.thread = None
        self.connected_device = None  # (ip, device_name, last_seen)
        self.on_device_connected = None
        self.on_device_disconnected = None
        self.active_cmd_sock = None

    def start(self):
        self.running = True
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.bind(("", DISCOVERY_PORT))
        self.thread = threading.Thread(target=self._listen_loop, daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass

    def send_command(self, cmd_str, target_ip=None):
        """Sends a remote control command to the iPhone (via active TCP socket or UDP)."""
        data = (cmd_str + "\n").encode("utf-8")
        if self.active_cmd_sock:
            try:
                self.active_cmd_sock.sendall(data)
                return True
            except Exception:
                self.active_cmd_sock = None
        if target_ip or (self.connected_device and self.connected_device[0]):
            ip = target_ip or self.connected_device[0]
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                s.sendto(data, (ip, DISCOVERY_PORT))
                s.close()
                return True
            except Exception:
                pass
        return False

    def _listen_loop(self):
        while self.running:
            try:
                data, addr = self.sock.recvfrom(2048)
                msg = data.decode("utf-8", errors="ignore").strip()
                if not msg:
                    continue

                if msg == "DISCOVER_CAMERA":
                    # Respond with camera server info
                    resp = f"BONAY_CAMERA_PC|{self.pc_name}|{VIDEO_TCP_PORT}|{VIDEO_UDP_PORT}"
                    self.sock.sendto(resp.encode("utf-8"), addr)

                elif msg.startswith("CONNECT_CAMERA|"):
                    parts = msg.split("|")
                    device_name = parts[1] if len(parts) > 1 else "iPhone"
                    self.connected_device = (addr[0], device_name, time.time())
                    if self.on_device_connected:
                        self.on_device_connected(addr[0], device_name)
                    ack = f"CONNECTED_ACK|{self.pc_name}"
                    self.sock.sendto(ack.encode("utf-8"), addr)

                elif msg == "PING":
                    if self.connected_device and self.connected_device[0] == addr[0]:
                        self.connected_device = (addr[0], self.connected_device[1], time.time())

                elif msg == "DISCONNECT":
                    if self.connected_device and self.connected_device[0] == addr[0]:
                        dev_ip = self.connected_device[0]
                        self.connected_device = None
                        if self.on_device_disconnected:
                            self.on_device_disconnected(dev_ip)

            except Exception:
                if not self.running:
                    break

    def check_timeout(self, timeout_secs=5.0):
        if self.connected_device:
            ip, name, last_seen = self.connected_device
            if time.time() - last_seen > timeout_secs:
                self.connected_device = None
                if self.on_device_disconnected:
                    self.on_device_disconnected(ip)
