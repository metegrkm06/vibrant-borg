import soundcard as sc
import pyogg.opus
import ctypes
import numpy as np

class OpusEncoder:
    def __init__(self, sample_rate=48000, channels=2, application=2049):
        err = ctypes.c_int()
        self.encoder = pyogg.opus.opus_encoder_create(sample_rate, channels, application, ctypes.byref(err))
        if err.value != 0:
            raise Exception(f"Failed to create Opus encoder: {err.value}")
            
    def encode(self, pcm_data: bytes, frame_size: int) -> bytes:
        out_buf = ctypes.create_string_buffer(4000)
        pcm_ptr = ctypes.cast(pcm_data, ctypes.POINTER(pyogg.opus.opus_int16))
        n = pyogg.opus.opus_encode(self.encoder, pcm_ptr, frame_size, out_buf, len(out_buf))
        if n < 0:
            raise Exception(f"Opus encode failed: {n}")
        return out_buf.raw[:n]

def main():
    try:
        mics = sc.all_microphones(include_loopback=True)
        loopback = next((m for m in mics if m.isloopback), None)
        print("Using loopback:", loopback.name if loopback else "None")
        
        enc = OpusEncoder()
        print("Encoder initialized!")
        
        # Test with dummy data
        dummy_pcm = np.zeros((960, 2), dtype=np.int16).tobytes()
        encoded = enc.encode(dummy_pcm, 960)
        print("Encoded length:", len(encoded))
        
    except Exception as e:
        print("Error:", e)

if __name__ == "__main__":
    main()
