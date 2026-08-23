import customtkinter as ctk
import socket
import threading
import time
from audio import AudioStreamer
from network import NetworkManager, trigger_media_key, VK_MEDIA_PLAY_PAUSE, VK_MEDIA_NEXT_TRACK, VK_MEDIA_PREV_TRACK
from usbmux import USBMux
import qrcode
from PIL import Image
import tkinter as tk

ctk.set_appearance_mode("System")
ctk.set_default_color_theme("blue")

class AppSelectorDialog(ctk.CTkToplevel):
    def __init__(self, parent, streamer: AudioStreamer):
        super().__init__(parent)
        self.title("Select Audio Apps")
        self.geometry("380x480")
        self.streamer = streamer
        self.grab_set()

        self.app_vars = {}
        self.app_list = []
        self.all_var = ctk.BooleanVar(value=streamer._all_system_audio)

        ctk.CTkLabel(self, text="Audio Source", font=ctk.CTkFont(size=18, weight="bold")).pack(pady=(20, 5))
        ctk.CTkLabel(self, text="Choose which apps' audio gets streamed.", text_color="gray").pack(pady=(0, 15))

        # All System Audio toggle
        all_frame = ctk.CTkFrame(self)
        all_frame.pack(fill="x", padx=20, pady=5)
        ctk.CTkLabel(all_frame, text="🔊 All System Audio", font=ctk.CTkFont(weight="bold")).pack(side="left", padx=10, pady=8)
        ctk.CTkSwitch(all_frame, variable=self.all_var, text="", command=self._toggle_all).pack(side="right", padx=10)

        ctk.CTkLabel(self, text="— or select specific apps —", text_color="gray", font=ctk.CTkFont(size=12)).pack(pady=5)

        # Scrollable app list
        self.scroll = ctk.CTkScrollableFrame(self, height=220)
        self.scroll.pack(fill="both", expand=True, padx=20, pady=5)

        self._load_apps()

        btn_frame = ctk.CTkFrame(self, fg_color="transparent")
        btn_frame.pack(fill="x", padx=20, pady=15)
        ctk.CTkButton(btn_frame, text="Apply", command=self._apply).pack(side="right", padx=5)
        ctk.CTkButton(btn_frame, text="Cancel", fg_color="gray", command=self.destroy).pack(side="right")

    def _load_apps(self):
        # Clear scroll frame
        for w in self.scroll.winfo_children():
            w.destroy()
        self.app_list = self.streamer.get_app_audio_sessions()
        selected = self.streamer._selected_apps
        state = "disabled" if self.all_var.get() else "normal"
        if not self.app_list:
            ctk.CTkLabel(self.scroll, text="No apps with audio found.\nPlay audio in an app first.", text_color="gray").pack(pady=20)
            return
        for app in self.app_list:
            name = app["name"]
            var = ctk.BooleanVar(value=name.lower() in selected)
            self.app_vars[name.lower()] = var
            row = ctk.CTkFrame(self.scroll)
            row.pack(fill="x", pady=2)
            ctk.CTkLabel(row, text=f"🎵  {name}").pack(side="left", padx=10, pady=6)
            sw = ctk.CTkSwitch(row, variable=var, text="", state=state)
            sw.pack(side="right", padx=10)

    def _toggle_all(self):
        # Refresh app switch states
        state = "disabled" if self.all_var.get() else "normal"
        for w in self.scroll.winfo_children():
            for child in w.winfo_children():
                if isinstance(child, ctk.CTkSwitch):
                    child.configure(state=state)

    def _apply(self):
        all_audio = self.all_var.get()
        selected = {name for name, var in self.app_vars.items() if var.get()}
        self.streamer.set_audio_mode(all_system=all_audio, selected_apps=selected)
        self.destroy()


class AudioStreamerApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("AudioStreamer — PC Server")
        self.geometry("660x520")

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

        self.usb_thread = threading.Thread(target=self._usb_monitor_loop, daemon=True)
        self.usb_thread.start()

        self.check_timeout_loop()

    def build_ui(self):
        self.grid_columnconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # ── Left Panel ──────────────────────────────────────────────
        left = ctk.CTkFrame(self)
        left.grid(row=0, column=0, padx=10, pady=10, sticky="nsew")

        self.status_label = ctk.CTkLabel(left, text="Waiting for device…",
                                          font=ctk.CTkFont(size=17, weight="bold"))
        self.status_label.pack(pady=(18, 4))

        self.device_label = ctk.CTkLabel(left, text="Plug in USB or connect via Wi-Fi",
                                          text_color="gray")
        self.device_label.pack(pady=4)

        self.usb_badge = ctk.CTkLabel(left, text="⚡ USB: Auto-detect ready",
                                       font=ctk.CTkFont(size=12, weight="bold"),
                                       text_color="#3498db")
        self.usb_badge.pack(pady=4)

        # Wi-Fi QR / IP picker
        ctk.CTkLabel(left, text="Wi-Fi — scan or type IP:", font=ctk.CTkFont(size=12)).pack(pady=(12, 2))
        self.ips = self._get_all_ips()
        self.ip_var = ctk.StringVar(value=self.ips[0] if self.ips else "127.0.0.1")
        ctk.CTkOptionMenu(left, values=self.ips, variable=self.ip_var,
                          command=self._update_qr).pack(pady=2)

        self.qr_label = ctk.CTkLabel(left, text="")
        self.qr_label.pack(pady=6)
        self._update_qr(self.ip_var.get())

        # ── Right Panel ─────────────────────────────────────────────
        right = ctk.CTkFrame(self)
        right.grid(row=0, column=1, padx=10, pady=10, sticky="nsew")

        ctk.CTkLabel(right, text="Audio Source",
                     font=ctk.CTkFont(size=16, weight="bold")).pack(pady=(18, 6))

        # WASAPI device picker
        sources = self.streamer.get_sources()
        self.source_var = ctk.StringVar(value=sources[0] if sources else "None")
        ctk.CTkOptionMenu(right, values=sources, variable=self.source_var,
                          command=self._change_source).pack(pady=6, padx=20, fill="x")

        # App selector button
        ctk.CTkButton(right, text="🎵  Select Apps to Stream",
                      command=self._open_app_selector).pack(pady=6, padx=20, fill="x")

        ctk.CTkLabel(right, text="Master Volume",
                     font=ctk.CTkFont(size=15, weight="bold")).pack(pady=(18, 6))

        self.volume_slider = ctk.CTkSlider(right, from_=0, to=2.0,
                                            command=self._change_volume)
        self.volume_slider.set(1.0)
        self.volume_slider.pack(pady=6, padx=20, fill="x")

        self.mute_btn = ctk.CTkButton(right, text="Mute", command=self._toggle_mute)
        self.mute_btn.pack(pady=14)
        self.is_muted = False

    # ── USB Monitor ─────────────────────────────────────────────────

    def _usb_monitor_loop(self):
        while self.running:
            try:
                devices = self.usbmux.get_devices(timeout=1.0)
                if devices and not self.is_usb_active:
                    dev = devices[0]
                    try:
                        sock = self.usbmux.connect_device(dev["DeviceID"], port=5002, timeout=2.0)
                        self.streamer.set_tcp_socket(sock)
                        self.is_usb_active = True
                        self.after(0, lambda d=dev: self.on_usb_connected(d))

                        cmd_t = threading.Thread(target=self._usb_cmd_reader, args=(sock,), daemon=True)
                        cmd_t.start()

                        while self.running and self.is_usb_active:
                            if self.streamer.tcp_sock is None:
                                break
                            time.sleep(0.5)

                        self.is_usb_active = False
                        self.streamer.set_tcp_socket(None)
                        self.after(0, self.on_usb_disconnected)
                    except Exception:
                        pass
            except Exception:
                pass
            time.sleep(1.5)

    def _usb_cmd_reader(self, sock):
        sock.settimeout(2.0)
        while self.is_usb_active and self.running:
            try:
                data = sock.recv(64)
                if not data:
                    break
                msg = data.decode("utf-8", errors="ignore").strip()
                if msg == "CMD|PLAY_PAUSE":
                    trigger_media_key(VK_MEDIA_PLAY_PAUSE)
                elif msg == "CMD|NEXT":
                    trigger_media_key(VK_MEDIA_NEXT_TRACK)
                elif msg == "CMD|PREV":
                    trigger_media_key(VK_MEDIA_PREV_TRACK)
                elif msg == "DISCONNECT":
                    self.is_usb_active = False
                    break
            except socket.timeout:
                continue
            except Exception:
                break

    # ── Helpers ──────────────────────────────────────────────────────

    def _get_all_ips(self):
        try:
            _, _, ips = socket.gethostbyname_ex(socket.gethostname())
            valid = [ip for ip in ips if not ip.startswith("127.")]
            return valid or [self._local_ip()]
        except Exception:
            return [self._local_ip()]

    def _local_ip(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except Exception:
            return "127.0.0.1"
        finally:
            s.close()

    def _update_qr(self, ip):
        qr = qrcode.make(f"audiostreamer://{ip}")
        qr.save("qr.png")
        img = ctk.CTkImage(light_image=Image.open("qr.png"), size=(120, 120))
        self.qr_label.configure(image=img)

    def _open_app_selector(self):
        AppSelectorDialog(self, self.streamer)

    # ── Callbacks ────────────────────────────────────────────────────

    def on_usb_connected(self, dev):
        self.status_label.configure(text="⚡ Streaming via USB Cable", text_color="#2ecc71")
        self.device_label.configure(text=f"Cable: {dev.get('ProductType', 'iPhone')}")
        self.usb_badge.configure(text="⚡ USB Active — ~0 ms latency", text_color="#2ecc71")

    def on_usb_disconnected(self):
        if not self.network.connected_device:
            self.status_label.configure(text="Waiting for device…", text_color="white")
            self.device_label.configure(text="Plug in USB or connect via Wi-Fi")
        self.usb_badge.configure(text="⚡ USB: Auto-detect ready", text_color="#3498db")

    def on_wifi_connected(self, ip, name):
        if not self.is_usb_active:
            self.status_label.configure(text="Streaming Live (Wi-Fi)", text_color="green")
            self.device_label.configure(text=f"{name}  ({ip})")
            self.streamer.set_target(ip, 5000)

    def on_wifi_disconnected(self, ip):
        if not self.is_usb_active:
            self.status_label.configure(text="Waiting for device…", text_color="white")
            self.device_label.configure(text="Plug in USB or connect via Wi-Fi")
            self.streamer.set_target(None)

    def _change_source(self, choice):
        self.streamer.stop()
        self.streamer.start(source_name=choice)

    def _change_volume(self, value):
        if not self.is_muted:
            self.streamer.volume = float(value)

    def _toggle_mute(self):
        self.is_muted = not self.is_muted
        self.mute_btn.configure(text="Unmute" if self.is_muted else "Mute")
        self.streamer.volume = 0.0 if self.is_muted else self.volume_slider.get()

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
