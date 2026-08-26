import socket
import threading
import time
import struct
import cv2
import numpy as np
import os
from datetime import datetime

try:
    import pyvirtualcam
    HAS_PYVIRTUALCAM = True
except ImportError:
    HAS_PYVIRTUALCAM = False

class CameraStreamReceiver:
    def __init__(self, width=1280, height=720, fps=30):
        self.target_width = width
        self.target_height = height
        self.target_fps = fps
        self.running = False

        # Live State
        self.current_frame = None       # BGR numpy array
        self.current_rgb_frame = None   # RGB numpy array
        self.frame_lock = threading.Lock()

        # Metrics
        self.fps_actual = 0.0
        self.latency_ms = 0
        self.bitrate_kbps = 0.0
        self.resolution_str = "0x0"
        self._frame_count = 0
        self._bytes_count = 0
        self._last_metrics_t = time.perf_counter()

        # PC-side Filters
        self.mirror_horizontal = False
        self.rotation_degrees = 0  # 0, 90, 180, 270
        self.brightness = 0        # -100 to 100
        self.contrast = 1.0        # 0.5 to 2.0

        # Virtual Camera
        self.vcam = None
        self.vcam_active = False
        self.vcam_error = ""

        # Recording
        self.is_recording = False
        self.video_writer = None
        self.record_filename = ""

        # Network connections
        self.tcp_server_sock = None
        self.udp_sock = None
        self.active_client_sock = None

    def start_servers(self, tcp_port=5003, udp_port=5004):
        self.running = True

        # TCP Server (for Wi-Fi TCP & local tunnels)
        self.tcp_server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.tcp_server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.tcp_server_sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.tcp_server_sock.bind(("", tcp_port))
        self.tcp_server_sock.listen(2)

        # UDP Receiver (for ultra-fast Wi-Fi UDP stream)
        self.udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        self.udp_sock.bind(("", udp_port))

        threading.Thread(target=self._tcp_accept_loop, daemon=True).start()
        threading.Thread(target=self._udp_recv_loop, daemon=True).start()

    def stop_servers(self):
        self.running = False
        self.stop_virtual_camera()
        self.stop_recording()
        if self.tcp_server_sock:
            try: self.tcp_server_sock.close()
            except Exception: pass
        if self.udp_sock:
            try: self.udp_sock.close()
            except Exception: pass
        if self.active_client_sock:
            try: self.active_client_sock.close()
            except Exception: pass

    # ─── Virtual Camera ────────────────────────────────────────────────────────

    def start_virtual_camera(self, width=1280, height=720, fps=30):
        if not HAS_PYVIRTUALCAM:
            self.vcam_error = "pyvirtualcam not installed"
            return False

        self.stop_virtual_camera()
        try:
            # Try UnityCapture device named BonayCamera first, or fallback to default
            try:
                self.vcam = pyvirtualcam.Camera(width=width, height=height, fps=fps,
                                                fmt=pyvirtualcam.PixelFormat.RGB,
                                                device="BonayCamera")
            except Exception:
                self.vcam = pyvirtualcam.Camera(width=width, height=height, fps=fps,
                                                fmt=pyvirtualcam.PixelFormat.RGB)
            self.vcam_active = True
            self.vcam_error = ""
            return True
        except Exception as e:
            self.vcam_active = False
            self.vcam_error = str(e)
            return False

    def stop_virtual_camera(self):
        if self.vcam:
            try:
                self.vcam.close()
            except Exception:
                pass
            self.vcam = None
        self.vcam_active = False

    # ─── TCP Ingestion (Length-prefixed frames) ─────────────────────────────────

    def handle_tcp_stream(self, sock):
        """Processes an incoming TCP video stream (from Wi-Fi or USB usbmuxd tunnel)."""
        self.active_client_sock = sock
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            while self.running:
                # 1. Read 16-byte frame header: [Magic 4B: 'BNCF'][Len 4B][TimestampNs 8B]
                hdr = self._recv_exact(sock, 16)
                if not hdr:
                    break

                magic, length, ts_ns = struct.unpack("!4sIQ", hdr)
                if magic != b"BNCF" or length > 10 * 1024 * 1024:
                    continue

                # 2. Read full frame payload (JPEG / encoded frame)
                payload = self._recv_exact(sock, length)
                if not payload:
                    break

                self._process_frame_payload(payload, ts_ns)
        except Exception:
            pass
        finally:
            if self.active_client_sock == sock:
                self.active_client_sock = None

    def _recv_exact(self, sock, n):
        data = bytearray()
        while len(data) < n:
            packet = sock.recv(n - len(data))
            if not packet:
                return None
            data.extend(packet)
        return bytes(data)

    def _tcp_accept_loop(self):
        while self.running:
            try:
                sock, _ = self.tcp_server_sock.accept()
                threading.Thread(target=self.handle_tcp_stream, args=(sock,), daemon=True).start()
            except Exception:
                if not self.running:
                    break

    # ─── UDP Ingestion ─────────────────────────────────────────────────────────

    def _udp_recv_loop(self):
        # UDP packets: [Magic 4B: 'BNCU'][Seq 4B][FragIdx 2B][FragTotal 2B][TimestampNs 8B][Data]
        assembler = {}  # seq -> {total: N, parts: {idx: bytes}, ts: ns}
        while self.running:
            try:
                packet, _ = self.udp_sock.recvfrom(65535)
                if len(packet) < 20:
                    continue

                magic, seq, frag_idx, frag_total, ts_ns = struct.unpack("!4sIHHQ", packet[:20])
                if magic != b"BNCU":
                    continue

                chunk = packet[20:]
                if seq not in assembler:
                    assembler[seq] = {"total": frag_total, "parts": {}, "ts": ts_ns}
                assembler[seq]["parts"][frag_idx] = chunk

                if len(assembler[seq]["parts"]) == frag_total:
                    full_data = b"".join(assembler[seq]["parts"][i] for i in range(frag_total))
                    del assembler[seq]
                    self._process_frame_payload(full_data, ts_ns)

                # Clean old unfinished sequences
                if len(assembler) > 20:
                    old_keys = sorted(assembler.keys())[:-10]
                    for k in old_keys:
                        del assembler[k]
            except Exception:
                if not self.running:
                    break

    # ─── Frame Processing & Filters ───────────────────────────────────────────

    def _process_frame_payload(self, jpeg_bytes, ts_ns):
        # Calculate Latency
        now_ns = time.time_ns()
        lat_ms = max(0, int((now_ns - ts_ns) / 1_000_000))

        # Decode JPEG into BGR image
        np_arr = np.frombuffer(jpeg_bytes, np.uint8)
        bgr = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if bgr is None:
            return

        # Apply Rotation (0, 90, 180 upside-down fix, 270)
        if self.rotation_degrees == 90:
            bgr = cv2.rotate(bgr, cv2.ROTATE_90_CLOCKWISE)
        elif self.rotation_degrees == 180:
            bgr = cv2.rotate(bgr, cv2.ROTATE_180)
        elif self.rotation_degrees == 270:
            bgr = cv2.rotate(bgr, cv2.ROTATE_90_COUNTERCLOCKWISE)

        # Apply Mirror (Horizontal Flip)
        if self.mirror_horizontal:
            bgr = cv2.flip(bgr, 1)

        # Apply Brightness & Contrast
        if self.brightness != 0 or self.contrast != 1.0:
            bgr = cv2.convertScaleAbs(bgr, alpha=self.contrast, beta=self.brightness)

        # RGB conversion for GUI & Virtual Cam
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        h, w, _ = bgr.shape

        with self.frame_lock:
            self.current_frame = bgr
            self.current_rgb_frame = rgb
            self.latency_ms = lat_ms
            self.resolution_str = f"{w}x{h}"
            self._frame_count += 1
            self._bytes_count += len(jpeg_bytes)

            # Record frame if active
            if self.is_recording and self.video_writer:
                self.video_writer.write(bgr)

        # Send to Virtual Camera
        if self.vcam_active and self.vcam:
            try:
                # Resize if dimensions differ from virtual cam configuration
                if rgb.shape[1] != self.vcam.width or rgb.shape[0] != self.vcam.height:
                    frame_to_send = cv2.resize(rgb, (self.vcam.width, self.vcam.height))
                else:
                    frame_to_send = rgb
                self.vcam.send(frame_to_send)
            except Exception:
                pass

        # Update Metrics every 0.5s
        t_now = time.perf_counter()
        dt = t_now - self._last_metrics_t
        if dt >= 0.5:
            self.fps_actual = self._frame_count / dt
            self.bitrate_kbps = (self._bytes_count * 8 / 1024) / dt
            self._frame_count = 0
            self._bytes_count = 0
            self._last_metrics_t = t_now

    # ─── Snapshot & Recording ──────────────────────────────────────────────────

    def take_snapshot(self, save_dir="."):
        with self.frame_lock:
            if self.current_frame is None:
                return None
            frame = self.current_frame.copy()

        os.makedirs(save_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = os.path.join(save_dir, f"BonayCamera_Snapshot_{ts}.jpg")
        cv2.imwrite(filename, frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
        return filename

    def start_recording(self, save_dir=".", fps=30):
        with self.frame_lock:
            if self.current_frame is None or self.is_recording:
                return False
            h, w, _ = self.current_frame.shape

        os.makedirs(save_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.record_filename = os.path.join(save_dir, f"BonayCamera_Record_{ts}.mp4")
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        self.video_writer = cv2.VideoWriter(self.record_filename, fourcc, fps, (w, h))
        self.is_recording = True
        return self.record_filename

    def stop_recording(self):
        self.is_recording = False
        if self.video_writer:
            self.video_writer.release()
            self.video_writer = None
        return self.record_filename
