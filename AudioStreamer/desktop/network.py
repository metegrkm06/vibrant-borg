import socket
import threading
import json
import time
import ctypes

VK_MEDIA_NEXT_TRACK = 0xB0
VK_MEDIA_PREV_TRACK = 0xB1
VK_MEDIA_PLAY_PAUSE = 0xB3

def trigger_media_key(key_code):
    try:
        ctypes.windll.user32.keybd_event(key_code, 0, 0, 0)
        time.sleep(0.02)
        ctypes.windll.user32.keybd_event(key_code, 0, 2, 0) # KEYEVENTF_KEYUP
    except Exception as e:
        print(f"Media key error: {e}")

class NetworkManager:
    def __init__(self, pc_name="My PC"):
        self.pc_name = pc_name
        self.discovery_port = 5001
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("", self.discovery_port))
        
        self.is_running = False
        self._thread = None
        self.on_device_connected = None
        self.on_device_disconnected = None
        
        self.connected_device = None
        self.last_ping = 0
        
    def start(self):
        self.is_running = True
        self._thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._thread.start()
        
    def stop(self):
        self.is_running = False
        try:
            self.sock.close()
        except Exception:
            pass
        
    def _listen_loop(self):
        while self.is_running:
            try:
                data, addr = self.sock.recvfrom(1024)
                msg = data.decode('utf-8')
                
                if msg == "DISCOVER":
                    # Respond with PC Name and IP
                    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                    try:
                        s.connect(('10.255.255.255', 1))
                        my_ip = s.getsockname()[0]
                    except:
                        my_ip = '127.0.0.1'
                    finally:
                        s.close()
                    response = f"AUDIOSTREAMER_PC|{self.pc_name}|{my_ip}"
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
                        
                elif msg == "CMD|PLAY_PAUSE":
                    trigger_media_key(VK_MEDIA_PLAY_PAUSE)
                    
                elif msg == "CMD|NEXT":
                    trigger_media_key(VK_MEDIA_NEXT_TRACK)
                    
                elif msg == "CMD|PREV":
                    trigger_media_key(VK_MEDIA_PREV_TRACK)
                        
                elif msg == "DISCONNECT":
                    if self.connected_device and self.connected_device[0] == addr[0]:
                        if self.on_device_disconnected:
                            self.on_device_disconnected(self.connected_device[0])
                        self.connected_device = None
                        
            except Exception as e:
                if self.is_running:
                    print(f"Network error: {e}")

    def check_timeout(self):
        if self.connected_device and time.time() - self.last_ping > 5.0:
            if self.on_device_disconnected:
                self.on_device_disconnected(self.connected_device[0])
            self.connected_device = None
