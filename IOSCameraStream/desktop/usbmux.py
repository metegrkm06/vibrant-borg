import socket
import struct
import plistlib
import sys

USBMUXD_PORT = 27015

class USBMux:
    """
    Client for Apple's usbmuxd daemon on Windows.
    Allows tunneling TCP connections to iOS devices over standard USB Lightning/Type-C cable.
    """
    def __init__(self, host="127.0.0.1", port=USBMUXD_PORT):
        self.host = host
        self.port = port

    def _send_plist(self, sock, payload):
        data = plistlib.dumps(payload)
        length = len(data) + 16
        header = struct.pack("<IIII", length, 1, 8, 1)
        sock.sendall(header + data)

    def _recv_plist(self, sock):
        header = sock.recv(16)
        if len(header) < 16:
            return None
        length, version, request, tag = struct.unpack("<IIII", header)
        data = b""
        remaining = length - 16
        while remaining > 0:
            chunk = sock.recv(min(remaining, 4096))
            if not chunk:
                break
            data += chunk
            remaining -= len(chunk)
        return plistlib.loads(data)

    def get_devices(self, timeout=1.0):
        """Returns list of attached iOS device dicts: [{'DeviceID': int, 'SerialNumber': str, ...}]"""
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        try:
            sock.connect((self.host, self.port))
            req = {
                "ClientVersionString": "BonayCamera-1.0",
                "MessageType": "ListDevices",
                "ProgName": "BonayCamera"
            }
            self._send_plist(sock, req)
            resp = self._recv_plist(sock)
            if resp and "DeviceList" in resp:
                devices = []
                for entry in resp["DeviceList"]:
                    props = entry.get("Properties", {})
                    devices.append({
                        "DeviceID": entry.get("DeviceID"),
                        "SerialNumber": props.get("SerialNumber", ""),
                        "ProductType": props.get("ProductType", "iPhone"),
                        "DeviceName": props.get("DeviceName", "iPhone")
                    })
                return devices
        except Exception:
            return []
        finally:
            sock.close()
        return []

    def connect_device(self, device_id, port=5003, timeout=3.0):
        """
        Opens a raw TCP tunnel to the specified port on the iOS device via USB.
        Returns the connected socket.
        """
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024 * 1024)
        sock.settimeout(timeout)
        sock.connect((self.host, self.port))

        port_swapped = ((port << 8) & 0xFF00) | ((port >> 8) & 0x00FF)
        req = {
            "ClientVersionString": "BonayCamera-1.0",
            "MessageType": "Connect",
            "ProgName": "BonayCamera",
            "DeviceID": device_id,
            "PortNumber": port_swapped
        }
        self._send_plist(sock, req)
        resp = self._recv_plist(sock)
        if resp and resp.get("Number") == 0:
            sock.settimeout(None)
            return sock
        else:
            sock.close()
            err_num = resp.get("Number") if resp else "no response"
            raise Exception(f"usbmux connect failed (code {err_num})")
