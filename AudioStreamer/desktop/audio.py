import soundcard as sc
import numpy as np
import threading
import socket
import struct
import time

class AudioStreamer:
    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.tcp_sock = None
        self.is_streaming = False
        self.target_ip = None
        self.target_port = 5000
        self.volume = 1.0
        self.mic = None
        self._thread = None
        
        # Audio specs: 48kHz stereo, 20ms block size (960 samples)
        self.sample_rate = 48000
        self.frame_size = 960 
        
    def get_sources(self):
        mics = sc.all_microphones(include_loopback=True)
        return [m.name for m in mics if m.isloopback]
        
    def set_target(self, ip, port=5000):
        self.target_ip = ip
        self.target_port = port
        
    def set_tcp_socket(self, sock):
        self.tcp_sock = sock
        
    def start(self, source_name=None):
        if self.is_streaming:
            return
            
        mics = sc.all_microphones(include_loopback=True)
        if source_name:
            self.mic = next((m for m in mics if m.name == source_name and m.isloopback), None)
        if not self.mic:
            self.mic = next((m for m in mics if m.isloopback), None)
            
        if not self.mic:
            raise Exception("No loopback audio source found")
            
        self.is_streaming = True
        self._thread = threading.Thread(target=self._stream_loop, daemon=True)
        self._thread.start()
        
    def stop(self):
        self.is_streaming = False
        if self._thread:
            self._thread.join(timeout=1.0)
            
    def _stream_loop(self):
        seq = 0
        try:
            with self.mic.recorder(samplerate=self.sample_rate, channels=2, blocksize=self.frame_size) as rec:
                while self.is_streaming:
                    # Record returns float32 array
                    data = rec.record(numframes=self.frame_size)
                    
                    # Apply volume
                    if self.volume != 1.0:
                        data = data * self.volume
                        
                    # Convert float32 to int16 with clipping protection
                    data = np.clip(data, -1.0, 1.0)
                    data_int16 = (data * 32767.0).astype(np.int16)
                    
                    if self.target_ip or self.tcp_sock:
                        # Packet format: Sequence(4 bytes), Timestamp(8 bytes), PCMData(3840 bytes)
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
                                # Length prefix for TCP framing
                                framed = struct.pack("!I", len(packet)) + packet
                                self.tcp_sock.sendall(framed)
                            except Exception:
                                self.tcp_sock = None # Disconnected
                                
                    seq += 1
        except Exception as e:
            print(f"Stream loop error: {e}")
            self.is_streaming = False
