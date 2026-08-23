import soundcard as sc
import numpy as np
import threading
import socket
import struct
import time
from collections import deque

SAMPLE_RATE = 48000
CHANNELS = 2
FRAME_SAMPLES = 480   # 10ms @ 48kHz — smallest stable WASAPI block
BYTES_PER_FRAME = FRAME_SAMPLES * CHANNELS * 2  # int16

class AudioStreamer:
    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
        self.tcp_sock = None
        self.is_streaming = False
        self.target_ip = None
        self.target_port = 5000
        self.volume = 1.0
        self._thread = None

        # Per-app mix state
        self._all_system_audio = True
        self._selected_apps = set()   # set of session PIDs or names

    def get_sources(self):
        """Returns list of WASAPI loopback sources (whole-device)."""
        mics = sc.all_microphones(include_loopback=True)
        return [m.name for m in mics if m.isloopback]

    def get_app_audio_sessions(self):
        """Returns list of (pid, name, volume) for apps producing audio."""
        try:
            from pycaw.pycaw import AudioUtilities
            sessions = AudioUtilities.GetAllSessions()
            apps = []
            for s in sessions:
                if s.Process:
                    apps.append({
                        "pid": s.Process.pid,
                        "name": s.Process.name().replace(".exe", ""),
                        "session": s
                    })
            return apps
        except Exception as e:
            return []

    def set_target(self, ip, port=5000):
        self.target_ip = ip
        self.target_port = port

    def set_tcp_socket(self, sock):
        self.tcp_sock = sock

    def set_audio_mode(self, all_system: bool, selected_apps: set = None):
        self._all_system_audio = all_system
        self._selected_apps = selected_apps or set()

    def start(self, source_name=None):
        if self.is_streaming:
            return
        mics = sc.all_microphones(include_loopback=True)
        if source_name:
            self.mic = next((m for m in mics if m.name == source_name and m.isloopback), None)
        else:
            self.mic = None
        if not self.mic:
            self.mic = next((m for m in mics if m.isloopback), None)
        if not self.mic:
            raise Exception("No loopback audio source found. Make sure a sound device is active.")

        self.is_streaming = True
        self._thread = threading.Thread(target=self._stream_loop, daemon=True)
        self._thread.start()

    def stop(self):
        self.is_streaming = False
        if self._thread:
            self._thread.join(timeout=1.0)

    def _get_app_mix(self, full_data: np.ndarray) -> np.ndarray:
        """If per-app mode, mix only selected app volumes (mute others via pycaw)."""
        if self._all_system_audio:
            return full_data
        # Per-app: mute non-selected processes, capture loopback
        # (pycaw can set session volume to 0 for non-selected)
        try:
            from pycaw.pycaw import AudioUtilities
            sessions = AudioUtilities.GetAllSessions()
            for s in sessions:
                if s.Process and s.SimpleAudioVolume:
                    selected = s.Process.name().replace(".exe", "").lower() in self._selected_apps
                    s.SimpleAudioVolume.SetMute(not selected, None)
        except Exception:
            pass
        return full_data

    def _stream_loop(self):
        seq = 0
        # Set high priority for this thread
        try:
            import ctypes
            ctypes.windll.kernel32.SetThreadPriority(
                ctypes.windll.kernel32.GetCurrentThread(), 15)  # THREAD_PRIORITY_TIME_CRITICAL
        except Exception:
            pass

        try:
            with self.mic.recorder(samplerate=SAMPLE_RATE, channels=CHANNELS,
                                   blocksize=FRAME_SAMPLES) as rec:
                while self.is_streaming:
                    data = rec.record(numframes=FRAME_SAMPLES)  # float32 [480, 2]

                    if not self._all_system_audio:
                        data = self._get_app_mix(data)

                    if self.volume != 1.0:
                        data *= self.volume

                    np.clip(data, -1.0, 1.0, out=data)
                    data_int16 = (data * 32767.0).astype(np.int16)

                    ts = time.time_ns()
                    header = struct.pack("!IQ", seq, ts)
                    packet = header + data_int16.tobytes()

                    if self.target_ip:
                        try:
                            self.sock.sendto(packet, (self.target_ip, self.target_port))
                        except Exception:
                            pass

                    if self.tcp_sock:
                        try:
                            frame = struct.pack("!I", len(packet)) + packet
                            self.tcp_sock.sendall(frame)
                        except Exception:
                            self.tcp_sock = None

                    seq = (seq + 1) & 0xFFFFFFFF
        except Exception as e:
            print(f"Stream loop error: {e}")
        finally:
            # Restore all app volumes on exit
            if not self._all_system_audio:
                try:
                    from pycaw.pycaw import AudioUtilities
                    for s in AudioUtilities.GetAllSessions():
                        if s.SimpleAudioVolume:
                            s.SimpleAudioVolume.SetMute(False, None)
                except Exception:
                    pass
            self.is_streaming = False
