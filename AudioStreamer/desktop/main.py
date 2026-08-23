import customtkinter as ctk
import socket
import threading
import time
from audio import AudioStreamer
from network import NetworkManager, trigger_media_key, VK_MEDIA_PLAY_PAUSE, VK_MEDIA_NEXT_TRACK, VK_MEDIA_PREV_TRACK
from usbmux import USBMux
import qrcode
from PIL import Image
import os

ctk.set_appearance_mode("System")
ctk.set_default_color_theme("blue")

class AudioStreamerApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        
        self.title("AudioStreamer - PC Server (Wi-Fi & USB Cable)")
        self.geometry("640x500")
        
        self.streamer = AudioStreamer()
        self.network = NetworkManager(pc_name=socket.gethostname())
        self.usbmux = USBMux()
        
        self.network.on_device_connected = self.on_wifi_connected
        self.network.on_device_disconnected = self.on_wifi_disconnected
        
        self.is_usb_active = False
        self.running = True
        
        self.build_ui()
        
        self.network.start()
        self.streamer.start()
        
        # Start USB auto-connect thread
        self.usb_thread = threading.Thread(target=self._usb_monitor_loop, daemon=True)
        self.usb_thread.start()
        
        self.check_timeout_loop()
        
    def build_ui(self):
        self.grid_columnconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)
        
        # Left Panel (Status & QR)
        self.left_frame = ctk.CTkFrame(self)
        self.left_frame.grid(row=0, column=0, padx=10, pady=10, sticky="nsew")
        
        self.status_label = ctk.CTkLabel(self.left_frame, text="Waiting for device...", font=ctk.CTkFont(size=18, weight="bold"))
        self.status_label.pack(pady=(15, 5))
        
        self.device_label = ctk.CTkLabel(self.left_frame, text="Plug in USB cable or connect via Wi-Fi", text_color="gray")
        self.device_label.pack(pady=5)
        
        self.usb_badge = ctk.CTkLabel(self.left_frame, text="⚡ USB Cable: Ready (Auto-detect)", font=ctk.CTkFont(size=12, weight="bold"), text_color="#3498db")
        self.usb_badge.pack(pady=5)
        
        # IP Selection & QR Code for Wi-Fi
        ctk.CTkLabel(self.left_frame, text="Wi-Fi Connection Info:", font=ctk.CTkFont(size=12)).pack(pady=(10, 2))
        self.ips = self.get_all_ips()
        self.ip_var = ctk.StringVar(value=self.ips[0] if self.ips else "127.0.0.1")
        
        self.ip_menu = ctk.CTkOptionMenu(self.left_frame, values=self.ips, variable=self.ip_var, command=self.update_qr)
        self.ip_menu.pack(pady=3)
        
        self.qr_label = ctk.CTkLabel(self.left_frame, text="")
        self.qr_label.pack(pady=5)
        self.update_qr(self.ip_var.get())
        
        # Right Panel (Controls)
        self.right_frame = ctk.CTkFrame(self)
        self.right_frame.grid(row=0, column=1, padx=10, pady=10, sticky="nsew")
        
        ctk.CTkLabel(self.right_frame, text="Audio Source (WASAPI)", font=ctk.CTkFont(size=16, weight="bold")).pack(pady=10)
        
        sources = self.streamer.get_sources()
        self.source_var = ctk.StringVar(value=sources[0] if sources else "None")
        self.source_menu = ctk.CTkOptionMenu(self.right_frame, values=sources, variable=self.source_var, command=self.change_source)
        self.source_menu.pack(pady=10, padx=20, fill="x")
        
        ctk.CTkLabel(self.right_frame, text="Master Volume", font=ctk.CTkFont(size=16, weight="bold")).pack(pady=(20, 10))
        
        self.volume_slider = ctk.CTkSlider(self.right_frame, from_=0, to=2.0, command=self.change_volume)
        self.volume_slider.set(1.0)
        self.volume_slider.pack(pady=10, padx=20, fill="x")
        
        self.mute_btn = ctk.CTkButton(self.right_frame, text="Mute", command=self.toggle_mute)
        self.mute_btn.pack(pady=15)
        self.is_muted = False
        
    def _usb_monitor_loop(self):
        while self.running:
            try:
                devices = self.usbmux.get_devices(timeout=1.0)
                if devices and not self.is_usb_active:
                    dev = devices[0]
                    dev_id = dev["DeviceID"]
                    try:
                        sock = self.usbmux.connect_device(dev_id, port=5002, timeout=2.0)
                        self.streamer.set_tcp_socket(sock)
                        self.is_usb_active = True
                        self.after(0, lambda: self.on_usb_connected(dev))
                        
                        # Start reader for media commands from iOS over USB
                        cmd_thread = threading.Thread(target=self._usb_cmd_reader, args=(sock,), daemon=True)
                        cmd_thread.start()
                        
                        # Monitor socket connection
                        while self.running and self.is_usb_active:
                            if self.streamer.tcp_sock is None:
                                break
                            time.sleep(1.0)
                            
                        self.is_usb_active = False
                        self.streamer.set_tcp_socket(None)
                        self.after(0, self.on_usb_disconnected)
                    except Exception:
                        pass
            except Exception:
                pass
            time.sleep(1.5)

    def _usb_cmd_reader(self, sock):
        while self.is_usb_active and self.running:
            try:
                data = sock.recv(1024)
                if not data:
                    break
                msg = data.decode('utf-8', errors='ignore').strip()
                if msg == "CMD|PLAY_PAUSE":
                    trigger_media_key(VK_MEDIA_PLAY_PAUSE)
                elif msg == "CMD|NEXT":
                    trigger_media_key(VK_MEDIA_NEXT_TRACK)
                elif msg == "CMD|PREV":
                    trigger_media_key(VK_MEDIA_PREV_TRACK)
                elif msg == "DISCONNECT":
                    self.is_usb_active = False
                    break
            except Exception:
                break

    def get_all_ips(self):
        try:
            _, _, ips = socket.gethostbyname_ex(socket.gethostname())
            valid_ips = [ip for ip in ips if not ip.startswith("127.")]
            if not valid_ips:
                valid_ips = [self.get_local_ip()]
            return valid_ips
        except:
            return [self.get_local_ip()]
            
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
        
    def update_qr(self, ip_addr):
        qr = qrcode.make(f"audiostreamer://{ip_addr}")
        qr.save("qr.png")
        self.qr_image = ctk.CTkImage(light_image=Image.open("qr.png"), size=(120, 120))
        self.qr_label.configure(image=self.qr_image)
        
    def on_usb_connected(self, dev):
        self.status_label.configure(text="⚡ Streaming over USB", text_color="#2ecc71")
        self.device_label.configure(text=f"Direct Cable: {dev.get('ProductType', 'iPhone')}")
        self.usb_badge.configure(text="⚡ USB Active: 0ms Latency Mode", text_color="#2ecc71")
        
    def on_usb_disconnected(self):
        if not self.network.connected_device:
            self.status_label.configure(text="Waiting for device...", text_color="white")
            self.device_label.configure(text="Plug in USB cable or connect via Wi-Fi")
        self.usb_badge.configure(text="⚡ USB Cable: Ready (Auto-detect)", text_color="#3498db")
        
    def on_wifi_connected(self, ip, name):
        if not self.is_usb_active:
            self.status_label.configure(text="Streaming Live (Wi-Fi)", text_color="green")
            self.device_label.configure(text=f"Connected to: {name} ({ip})")
            self.streamer.set_target(ip, 5000)
        
    def on_wifi_disconnected(self, ip):
        if not self.is_usb_active:
            self.status_label.configure(text="Waiting for device...", text_color="white")
            self.device_label.configure(text="Plug in USB cable or connect via Wi-Fi")
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
        self.running = False
        self.network.stop()
        self.streamer.stop()
        self.destroy()

if __name__ == "__main__":
    app = AudioStreamerApp()
    app.protocol("WM_DELETE_WINDOW", app.on_closing)
    app.mainloop()
