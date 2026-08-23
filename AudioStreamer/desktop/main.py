import customtkinter as ctk
import socket
import threading
from audio import AudioStreamer
from network import NetworkManager
import qrcode
from PIL import Image
import os

ctk.set_appearance_mode("System")
ctk.set_default_color_theme("blue")

class AudioStreamerApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        
        self.title("AudioStreamer - PC Server")
        self.geometry("600x450")
        
        self.streamer = AudioStreamer()
        self.network = NetworkManager(pc_name=socket.gethostname())
        
        self.network.on_device_connected = self.on_device_connected
        self.network.on_device_disconnected = self.on_device_disconnected
        
        self.build_ui()
        
        self.network.start()
        self.streamer.start()
        
        self.check_timeout_loop()
        
    def build_ui(self):
        self.grid_columnconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)
        
        # Left Panel (Status & QR)
        self.left_frame = ctk.CTkFrame(self)
        self.left_frame.grid(row=0, column=0, padx=10, pady=10, sticky="nsew")
        
        self.status_label = ctk.CTkLabel(self.left_frame, text="Waiting for connection...", font=ctk.CTkFont(size=18, weight="bold"))
        self.status_label.pack(pady=20)
        
        self.device_label = ctk.CTkLabel(self.left_frame, text="No device connected", text_color="gray")
        self.device_label.pack(pady=5)
        
        # QR Code for manual pairing (IP address)
        ip_addr = self.get_local_ip()
        qr = qrcode.make(f"audiostreamer://{ip_addr}")
        qr.save("qr.png")
        self.qr_image = ctk.CTkImage(light_image=Image.open("qr.png"), size=(150, 150))
        self.qr_label = ctk.CTkLabel(self.left_frame, image=self.qr_image, text="")
        self.qr_label.pack(pady=20)
        
        self.ip_label = ctk.CTkLabel(self.left_frame, text=f"IP: {ip_addr}")
        self.ip_label.pack(pady=5)
        
        # Right Panel (Controls)
        self.right_frame = ctk.CTkFrame(self)
        self.right_frame.grid(row=0, column=1, padx=10, pady=10, sticky="nsew")
        
        ctk.CTkLabel(self.right_frame, text="Audio Source", font=ctk.CTkFont(size=16, weight="bold")).pack(pady=10)
        
        sources = self.streamer.get_sources()
        self.source_var = ctk.StringVar(value=sources[0] if sources else "None")
        self.source_menu = ctk.CTkOptionMenu(self.right_frame, values=sources, variable=self.source_var, command=self.change_source)
        self.source_menu.pack(pady=10, padx=20, fill="x")
        
        ctk.CTkLabel(self.right_frame, text="Master Volume", font=ctk.CTkFont(size=16, weight="bold")).pack(pady=(20, 10))
        
        self.volume_slider = ctk.CTkSlider(self.right_frame, from_=0, to=2.0, command=self.change_volume)
        self.volume_slider.set(1.0)
        self.volume_slider.pack(pady=10, padx=20, fill="x")
        
        self.mute_btn = ctk.CTkButton(self.right_frame, text="Mute", command=self.toggle_mute)
        self.mute_btn.pack(pady=20)
        self.is_muted = False
        
    def get_local_ip(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(('10.255.255.255', 1))
            IP = s.getsockname()[0]
        except Exception:
            IP = '127.0.0.1'
        finally:
            s.close()
        return IP
        
    def on_device_connected(self, ip, name):
        self.status_label.configure(text="Streaming Live", text_color="green")
        self.device_label.configure(text=f"Connected to: {name} ({ip})")
        self.streamer.set_target(ip, 5000)
        
    def on_device_disconnected(self, ip):
        self.status_label.configure(text="Waiting for connection...", text_color="white")
        self.device_label.configure(text="No device connected")
        self.streamer.set_target(None)
        
    def change_source(self, choice):
        self.streamer.stop()
        self.streamer.start(source_name=choice)
        
    def change_volume(self, value):
        if not self.is_muted:
            self.streamer.volume = float(value)
            
    def toggle_mute(self):
        self.is_muted = not self.is_muted
        if self.is_muted:
            self.mute_btn.configure(text="Unmute")
            self.streamer.volume = 0.0
        else:
            self.mute_btn.configure(text="Mute")
            self.streamer.volume = self.volume_slider.get()
            
    def check_timeout_loop(self):
        self.network.check_timeout()
        self.after(2000, self.check_timeout_loop)
        
    def on_closing(self):
        self.network.stop()
        self.streamer.stop()
        self.destroy()

if __name__ == "__main__":
    app = AudioStreamerApp()
    app.protocol("WM_DELETE_WINDOW", app.on_closing)
    app.mainloop()
