import socket
import threading
import json
import time

class NetworkManager:
    def __init__(self, pc_name="My PC"):
        self.pc_name = pc_name
        self.discovery_port = 5001
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("", self.discovery_port))
        
        self.is_running = False
        self._thread = None
        self.on_device_connected = None # Callback(ip, device_name)
        self.on_device_disconnected = None
        
        self.connected_device = None
        self.last_ping = 0
        
    def start(self):
        self.is_running = True
        self._thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._thread.start()
        
    def stop(self):
        self.is_running = False
        self.sock.close()
        
    def _listen_loop(self):
        while self.is_running:
            try:
                data, addr = self.sock.recvfrom(1024)
                msg = data.decode('utf-8')
                
                if msg == "DISCOVER":
                    # Respond with PC Name
                    response = f"AUDIOSTREAMER_PC|{self.pc_name}"
                    self.sock.sendto(response.encode('utf-8'), addr)
                    
                elif msg.startswith("CONNECT|"):
                    device_name = msg.split("|")[1]
                    self.connected_device = (addr[0], device_name)
                    self.last_ping = time.time()
                    if self.on_device_connected:
                        self.on_device_connected(addr[0], device_name)
                        
                elif msg == "PING":
                    if self.connected_device and self.connected_device[0] == addr[0]:
                        self.last_ping = time.time()
                        
                elif msg == "DISCONNECT":
                    if self.connected_device and self.connected_device[0] == addr[0]:
                        if self.on_device_disconnected:
                            self.on_device_disconnected(self.connected_device[0])
                        self.connected_device = None
                        
            except Exception as e:
                if self.is_running:
                    print(f"Network error: {e}")

        
    def check_timeout(self):
        # Call this periodically from main thread to drop stale connections
        if self.connected_device and time.time() - self.last_ping > 5.0:
            if self.on_device_disconnected:
                self.on_device_disconnected(self.connected_device[0])
            self.connected_device = None
