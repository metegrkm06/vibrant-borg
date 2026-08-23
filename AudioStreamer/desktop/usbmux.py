import socket
import struct
import plistlib
import threading
import time

class USBMux:
    def __init__(self, host="127.0.0.1", port=27015):
        self.host = host
        self.port = port
        
    def _send_packet(self, sock, payload_dict, tag=1):
        payload = plistlib.dumps(payload_dict)
        length = 16 + len(payload)
        header = struct.pack("<IIII", length, 1, 8, tag)
        sock.sendall(header + payload)
        
    def _read_packet(self, sock):
        header = sock.recv(16)
        if len(header) < 16:
            return None
        length, version, request, tag = struct.unpack("<IIII", header)
        payload_len = length - 16
        payload = b""
        while len(payload) < payload_len:
            chunk = sock.recv(payload_len - len(payload))
            if not chunk:
                break
            payload += chunk
        return plistlib.loads(payload)

    def get_devices(self, timeout=1.0):
        """Returns list of attached USB device IDs"""
        devices = []
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(timeout)
            s.connect((self.host, self.port))
            
            self._send_packet(s, {
                "MessageType": "Listen",
                "ClientVersionString": "AudioStreamer-1.0",
                "ProgName": "AudioStreamer"
            })
            
            # Read until timeout or we collect devices
            start = time.time()
            while time.time() - start < timeout:
                try:
                    pkt = self._read_packet(s)
                    if not pkt:
                        break
                    if pkt.get("MessageType") == "Attached":
                        dev_id = pkt.get("DeviceID")
                        props = pkt.get("Properties", {})
                        if props.get("ConnectionType") == "USB" and dev_id is not None:
                            devices.append({
                                "DeviceID": dev_id,
                                "SerialNumber": props.get("SerialNumber", "Unknown"),
                                "ProductType": props.get("ProductType", "iPhone")
                            })
                except socket.timeout:
                    break
            s.close()
        except Exception as e:
            pass
        return devices

    def connect_device(self, device_id, port=5002, timeout=3.0):
        """Connects to a specific port on the iOS device via USB, returns raw TCP socket"""
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((self.host, self.port))
        
        # Request Connect
        # Note: PortNumber in usbmuxd is big endian / network byte order
        port_num = socket.htons(port)
        self._send_packet(s, {
            "MessageType": "Connect",
            "ClientVersionString": "AudioStreamer-1.0",
            "ProgName": "AudioStreamer",
            "DeviceID": device_id,
            "PortNumber": port_num
        })
        
        pkt = self._read_packet(s)
        if pkt and pkt.get("MessageType") == "Result" and pkt.get("Number") == 0:
            # Connection succeeded! Remove timeout and return raw socket
            s.settimeout(None)
            return s
        else:
            s.close()
            err_num = pkt.get("Number") if pkt else "No response"
            raise ConnectionError(f"usbmuxd Connect failed with code: {err_num}")
