import customtkinter as ctk
import tkinter as tk
from PIL import Image, ImageTk
import socket
import threading
import time
import os
import subprocess
import qrcode

from camera_stream import CameraStreamReceiver, HAS_PYVIRTUALCAM
from network import NetworkManager, DISCOVERY_PORT, VIDEO_TCP_PORT, VIDEO_UDP_PORT
from usbmux import USBMux

ctk.set_appearance_mode("Dark")
ctk.set_default_color_theme("blue")

class BonayCameraDesktopApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("BonayCamera — iPhone Webcam & Stream Studio")
        self.geometry("1100x740")
        self.minsize(960, 680)

        # Core Components
        self.receiver = CameraStreamReceiver()
        self.network = NetworkManager(pc_name=socket.gethostname())
        self.usbmux = USBMux()

        self.network.on_device_connected = self.on_wifi_connected
        self.network.on_device_disconnected = self.on_wifi_disconnected

        # State
        self.running = True
        self.is_usb_active = False
        self.is_fullscreen = False

        # Build UI
        self.build_ui()

        # Start Services
        self.receiver.start_servers(tcp_port=VIDEO_TCP_PORT, udp_port=VIDEO_UDP_PORT)
        self.network.start()

        # Start USB Monitor Thread
        self.usb_thread = threading.Thread(target=self._usb_monitor_loop, daemon=True)
        self.usb_thread.start()

        # Start Preview GUI Refresh Loop
        self.after(30, self._update_preview_loop)
        self.after(2000, self._check_network_timeout)

    def build_ui(self):
        self.grid_columnconfigure(0, weight=3) # Preview pane
        self.grid_columnconfigure(1, weight=2) # Controls pane
        self.grid_rowconfigure(0, weight=1)

        # ═════════════════════════════════════════════════════════════════════════
        # LEFT PANEL: Live Camera Preview & Action Buttons
        # ═════════════════════════════════════════════════════════════════════════
        left_panel = ctk.CTkFrame(self, corner_radius=12)
        left_panel.grid(row=0, column=0, padx=(12, 6), pady=12, sticky="nsew")
        left_panel.grid_rowconfigure(0, weight=1)
        left_panel.grid_columnconfigure(0, weight=1)

        # Canvas for video rendering
        self.preview_container = ctk.CTkFrame(left_panel, fg_color="#101216", corner_radius=8)
        self.preview_container.grid(row=0, column=0, padx=10, pady=(10, 6), sticky="nsew")
        self.preview_container.grid_rowconfigure(0, weight=1)
        self.preview_container.grid_columnconfigure(0, weight=1)

        self.video_canvas = tk.Canvas(self.preview_container, bg="#101216", highlightthickness=0)
        self.video_canvas.grid(row=0, column=0, sticky="nsew")
        self.video_canvas.bind("<Double-Button-1>", lambda e: self._toggle_fullscreen())

        # No Signal Placeholder Label
        self.no_signal_label = ctk.CTkLabel(
            self.preview_container,
            text="📱 Connect iPhone via USB Cable or Wi-Fi\n\nWaiting for BonayCamera stream...",
            font=ctk.CTkFont(size=16, weight="bold"),
            text_color="#6c757d"
        )
        self.no_signal_label.place(relx=0.5, rely=0.5, anchor="center")

        # Live Metrics Overlay
        self.metrics_label = ctk.CTkLabel(
            self.preview_container,
            text="● OFF  |  0.0 FPS  |  0 ms  |  0x0  |  0 KB/s",
            font=ctk.CTkFont(family="Consolas", size=11, weight="bold"),
            fg_color="rgba(0,0,0,0.6)",
            text_color="#2ecc71",
            corner_radius=6,
            padx=8,
            pady=4
        )
        self.metrics_label.place(relx=0.02, rely=0.03, anchor="nw")

        # Bottom Quick Action Bar
        action_bar = ctk.CTkFrame(left_panel, fg_color="transparent")
        action_bar.grid(row=1, column=0, padx=10, pady=(4, 10), sticky="ew")

        self.btn_snapshot = ctk.CTkButton(action_bar, text="📸 Snapshot", width=100, command=self._on_snapshot)
        self.btn_snapshot.pack(side="left", padx=4)

        self.btn_record = ctk.CTkButton(action_bar, text="⏺ Record", width=95, fg_color="#e74c3c", hover_color="#c0392b", command=self._on_toggle_record)
        self.btn_record.pack(side="left", padx=4)

        self.btn_mirror = ctk.CTkButton(action_bar, text="🪞 Mirror", width=85, fg_color="#34495e", hover_color="#2c3e50", command=self._on_toggle_mirror)
        self.btn_mirror.pack(side="left", padx=4)

        self.btn_rotate = ctk.CTkButton(action_bar, text="🔄 Rotate 0°", width=105, fg_color="#34495e", hover_color="#2c3e50", command=self._on_cycle_rotation)
        self.btn_rotate.pack(side="left", padx=4)

        self.btn_fullscreen = ctk.CTkButton(action_bar, text="⛶ Fullscreen", width=100, fg_color="#34495e", hover_color="#2c3e50", command=self._toggle_fullscreen)
        self.btn_fullscreen.pack(side="right", padx=4)

        # ═════════════════════════════════════════════════════════════════════════
        # RIGHT PANEL: Connection Status, Remote Controls, Virtual Cam Settings
        # ═════════════════════════════════════════════════════════════════════════
        right_panel = ctk.CTkScrollableFrame(self, corner_radius=12)
        right_panel.grid(row=0, column=1, padx=(6, 12), pady=12, sticky="nsew")

        # ── 1. Connection Header ──
        conn_box = ctk.CTkFrame(right_panel, corner_radius=10)
        conn_box.pack(fill="x", padx=4, pady=4)

        self.status_title = ctk.CTkLabel(conn_box, text="Waiting for iPhone...", font=ctk.CTkFont(size=16, weight="bold"))
        self.status_title.pack(pady=(12, 2))

        self.status_sub = ctk.CTkLabel(conn_box, text="Plug in Lightning/USB cable or connect to same Wi-Fi", text_color="gray", font=ctk.CTkFont(size=12))
        self.status_sub.pack(pady=(0, 8))

        self.usb_badge = ctk.CTkLabel(
            conn_box,
            text="⚡ USB: Auto-detect Ready (usbmuxd)",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#3498db"
        )
        self.usb_badge.pack(pady=(0, 10))

        # Wi-Fi IP & QR Code
        wifi_frame = ctk.CTkFrame(conn_box, fg_color="#1a1c23", corner_radius=8)
        wifi_frame.pack(fill="x", padx=10, pady=(0, 10))

        ctk.CTkLabel(wifi_frame, text="Wi-Fi Manual IP / QR Code:", font=ctk.CTkFont(size=12, weight="bold")).pack(pady=(6, 2))
        self.ips = self._get_all_ips()
        self.ip_var = ctk.StringVar(value=self.ips[0] if self.ips else "127.0.0.1")
        ctk.CTkOptionMenu(wifi_frame, values=self.ips, variable=self.ip_var, command=self._update_qr).pack(pady=4)

        self.qr_label = ctk.CTkLabel(wifi_frame, text="")
        self.qr_label.pack(pady=6)
        self._update_qr(self.ip_var.get())

        # ── 2. Remote Phone Camera Controls ──
        ctrl_box = ctk.CTkFrame(right_panel, corner_radius=10)
        ctrl_box.pack(fill="x", padx=4, pady=8)

        ctk.CTkLabel(ctrl_box, text="📱 Remote Phone Controls", font=ctk.CTkFont(size=15, weight="bold")).pack(pady=(10, 6))

        # Camera Switcher Buttons (0.5x Ultra-Wide, 1x Wide, 2x Tele, Front)
        ctk.CTkLabel(ctrl_box, text="Switch Camera Lens:", text_color="gray", font=ctk.CTkFont(size=12)).pack(anchor="w", padx=15, pady=(4, 2))
        cam_btn_frame = ctk.CTkFrame(ctrl_box, fg_color="transparent")
        cam_btn_frame.pack(fill="x", padx=10, pady=4)
        cam_btn_frame.grid_columnconfigure((0, 1, 2, 3), weight=1)

        self.btn_cam_front = ctk.CTkButton(cam_btn_frame, text="Front 🤳", height=32, command=lambda: self._send_cmd("CMD|CAM|FRONT"))
        self.btn_cam_front.grid(row=0, column=0, padx=2, pady=2, sticky="ew")

        self.btn_cam_wide = ctk.CTkButton(cam_btn_frame, text="1.0x 📷", height=32, command=lambda: self._send_cmd("CMD|CAM|BACK_WIDE"))
        self.btn_cam_wide.grid(row=0, column=1, padx=2, pady=2, sticky="ew")

        self.btn_cam_ultra = ctk.CTkButton(cam_btn_frame, text="0.5x 🌐", height=32, command=lambda: self._send_cmd("CMD|CAM|BACK_ULTRA_WIDE"))
        self.btn_cam_ultra.grid(row=0, column=2, padx=2, pady=2, sticky="ew")

        self.btn_cam_tele = ctk.CTkButton(cam_btn_frame, text="2.0x 🔭", height=32, command=lambda: self._send_cmd("CMD|CAM|BACK_TELE"))
        self.btn_cam_tele.grid(row=0, column=3, padx=2, pady=2, sticky="ew")

        # Torch / Flashlight Toggle
        torch_frame = ctk.CTkFrame(ctrl_box, fg_color="transparent")
        torch_frame.pack(fill="x", padx=15, pady=6)
        self.torch_var = ctk.BooleanVar(value=False)
        self.torch_switch = ctk.CTkSwitch(torch_frame, text="🔦 Phone Flashlight / Torch", variable=self.torch_var, command=self._on_toggle_torch)
        self.torch_switch.pack(side="left")

        # Resolution & FPS Selectors
        settings_grid = ctk.CTkFrame(ctrl_box, fg_color="transparent")
        settings_grid.pack(fill="x", padx=15, pady=6)
        settings_grid.grid_columnconfigure((0, 1), weight=1)

        ctk.CTkLabel(settings_grid, text="Resolution Preset:", text_color="gray", font=ctk.CTkFont(size=12)).grid(row=0, column=0, sticky="w", pady=(0, 2))
        ctk.CTkLabel(settings_grid, text="Target FPS:", text_color="gray", font=ctk.CTkFont(size=12)).grid(row=0, column=1, sticky="w", pady=(0, 2))

        self.res_menu = ctk.CTkOptionMenu(
            settings_grid,
            values=["1080p (1920x1080)", "720p (1280x720)", "480p (640x480)", "4K (3840x2160)"],
            command=self._on_change_resolution
        )
        self.res_menu.set("1080p (1920x1080)")
        self.res_menu.grid(row=1, column=0, padx=(0, 5), sticky="ew")

        self.fps_menu = ctk.CTkOptionMenu(
            settings_grid,
            values=["60 FPS", "30 FPS", "24 FPS", "15 FPS"],
            command=self._on_change_fps
        )
        self.fps_menu.set("60 FPS")
        self.fps_menu.grid(row=1, column=1, padx=(5, 0), sticky="ew")

        # Remote Zoom Slider
        ctk.CTkLabel(ctrl_box, text="Smooth Zoom Slider:", text_color="gray", font=ctk.CTkFont(size=12)).pack(anchor="w", padx=15, pady=(8, 2))
        self.zoom_slider = ctk.CTkSlider(ctrl_box, from_=0.5, to=5.0, number_of_steps=45, command=self._on_zoom_slider)
        self.zoom_slider.set(1.0)
        self.zoom_slider.pack(fill="x", padx=15, pady=(0, 12))

        # ── 3. BonayCamera Virtual Webcam Driver ──
        vcam_box = ctk.CTkFrame(right_panel, corner_radius=10)
        vcam_box.pack(fill="x", padx=4, pady=8)

        ctk.CTkLabel(vcam_box, text="🎥 BonayCamera Virtual Driver", font=ctk.CTkFont(size=15, weight="bold")).pack(pady=(10, 4))
        ctk.CTkLabel(vcam_box, text="Outputs stream into Discord, OBS, Zoom & Teams", text_color="gray", font=ctk.CTkFont(size=12)).pack(pady=(0, 8))

        # Virtual Cam Toggle Switch
        vcam_switch_frame = ctk.CTkFrame(vcam_box, fg_color="transparent")
        vcam_switch_frame.pack(fill="x", padx=15, pady=4)
        self.vcam_switch_var = ctk.BooleanVar(value=False)
        self.vcam_switch = ctk.CTkSwitch(vcam_switch_frame, text="Enable Virtual Camera Output", variable=self.vcam_switch_var, command=self._on_toggle_vcam)
        self.vcam_switch.pack(side="left")

        # Virtual Cam Status Label
        self.vcam_status_lbl = ctk.CTkLabel(vcam_box, text="● Virtual Cam Inactive", font=ctk.CTkFont(size=12), text_color="gray")
        self.vcam_status_lbl.pack(pady=4)

        # Install Driver 1-Click Button
        self.btn_install_driver = ctk.CTkButton(
            vcam_box,
            text="🛠  Install BonayCamera Driver (1-Click)",
            fg_color="#27ae60",
            hover_color="#219150",
            command=self._on_install_driver
        )
        self.btn_install_driver.pack(fill="x", padx=15, pady=(6, 12))

    # ═════════════════════════════════════════════════════════════════════════
    # USB Monitor Loop (usbmuxd port 27015 tunnel to 5003 on iOS)
    # ═════════════════════════════════════════════════════════════════════════
    def _usb_monitor_loop(self):
        while self.running:
            try:
                devices = self.usbmux.get_devices(timeout=1.0)
                if devices and not self.is_usb_active:
                    dev = devices[0]
                    try:
                        sock = self.usbmux.connect_device(dev["DeviceID"], port=VIDEO_TCP_PORT, timeout=2.0)
                        self.is_usb_active = True
                        self.network.active_cmd_sock = sock
                        self.after(0, lambda d=dev: self.on_usb_connected(d))

                        # Ingest video frames directly from USB tunnel
                        self.receiver.handle_tcp_stream(sock)

                        self.is_usb_active = False
                        self.network.active_cmd_sock = None
                        self.after(0, self.on_usb_disconnected)
                    except Exception:
                        pass
            except Exception:
                pass
            time.sleep(1.5)

    # ═════════════════════════════════════════════════════════════════════════
    # Callbacks & UI Event Handlers
    # ═════════════════════════════════════════════════════════════════════════
    def on_usb_connected(self, dev):
        name = dev.get("ProductType", "iPhone")
        self.status_title.configure(text="⚡ Connected via USB Cable", text_color="#2ecc71")
        self.status_sub.configure(text=f"Device: {name} (Zero Latency Direct Cable Mode)")
        self.usb_badge.configure(text="⚡ USB Active: ~2 ms Latency", text_color="#2ecc71")
        self.no_signal_label.place_forget()

    def on_usb_disconnected(self):
        if not self.network.connected_device:
            self.status_title.configure(text="Waiting for iPhone...", text_color="white")
            self.status_sub.configure(text="Plug in Lightning/USB cable or connect to same Wi-Fi")
            self.no_signal_label.place(relx=0.5, rely=0.5, anchor="center")
        self.usb_badge.configure(text="⚡ USB: Auto-detect Ready (usbmuxd)", text_color="#3498db")

    def on_wifi_connected(self, ip, name):
        if not self.is_usb_active:
            self.status_title.configure(text="🌐 Streaming via Wi-Fi", text_color="#2ecc71")
            self.status_sub.configure(text=f"Device: {name} ({ip})")
            self.no_signal_label.place_forget()

    def on_wifi_disconnected(self, ip):
        if not self.is_usb_active:
            self.status_title.configure(text="Waiting for iPhone...", text_color="white")
            self.status_sub.configure(text="Plug in Lightning/USB cable or connect to same Wi-Fi")
            self.no_signal_label.place(relx=0.5, rely=0.5, anchor="center")

    def _send_cmd(self, cmd_str):
        self.network.send_command(cmd_str)

    def _on_toggle_torch(self):
        state = "ON" if self.torch_var.get() else "OFF"
        self._send_cmd(f"CMD|TORCH|{state}")

    def _on_change_resolution(self, choice):
        if "1080p" in choice:
            self._send_cmd("CMD|QUALITY|1080P")
        elif "720p" in choice:
            self._send_cmd("CMD|QUALITY|720P")
        elif "480p" in choice:
            self._send_cmd("CMD|QUALITY|480P")
        elif "4K" in choice:
            self._send_cmd("CMD|QUALITY|4K")

    def _on_change_fps(self, choice):
        fps_val = choice.split()[0]
        self._send_cmd(f"CMD|FPS|{fps_val}")

    def _on_zoom_slider(self, val):
        self._send_cmd(f"CMD|ZOOM|{val:.2f}")

    def _on_toggle_mirror(self):
        self.receiver.mirror_horizontal = not self.receiver.mirror_horizontal
        self.btn_mirror.configure(fg_color="#2980b9" if self.receiver.mirror_horizontal else "#34495e")

    def _on_cycle_rotation(self):
        deg = (self.receiver.rotation_degrees + 90) % 360
        self.receiver.rotation_degrees = deg
        self.btn_rotate.configure(text=f"🔄 Rotate {deg}°")

    def _on_snapshot(self):
        path = self.receiver.take_snapshot()
        if path:
            self.btn_snapshot.configure(text="✓ Saved!", fg_color="#27ae60")
            self.after(1500, lambda: self.btn_snapshot.configure(text="📸 Snapshot", fg_color="#3a7ebf"))

    def _on_toggle_record(self):
        if not self.receiver.is_recording:
            res = self.receiver.start_recording()
            if res:
                self.btn_record.configure(text="⏹ Stop", fg_color="#c0392b")
        else:
            self.receiver.stop_recording()
            self.btn_record.configure(text="⏺ Record", fg_color="#e74c3c")

    def _on_toggle_vcam(self):
        if self.vcam_switch_var.get():
            ok = self.receiver.start_virtual_camera(width=1280, height=720, fps=30)
            if ok:
                self.vcam_status_lbl.configure(text="● BonayCamera LIVE in Discord/Zoom/OBS", text_color="#2ecc71")
            else:
                self.vcam_switch_var.set(False)
                self.vcam_status_lbl.configure(text=f"❌ Error: {self.receiver.vcam_error[:35]}", text_color="#e74c3c")
        else:
            self.receiver.stop_virtual_camera()
            self.vcam_status_lbl.configure(text="● Virtual Cam Inactive", text_color="gray")

    def _on_install_driver(self):
        driver_bat = os.path.join(os.path.dirname(__file__), "driver", "Install_BonayCamera_Driver.bat")
        if os.path.exists(driver_bat):
            try:
                subprocess.Popen(["cmd.exe", "/c", driver_bat], creationflags=subprocess.CREATE_NEW_CONSOLE)
            except Exception as e:
                print("Failed to run installer:", e)

    def _toggle_fullscreen(self):
        self.is_fullscreen = not self.is_fullscreen
        self.attributes("-fullscreen", self.is_fullscreen)

    # ═════════════════════════════════════════════════════════════════════════
    # Live Canvas Video Refresh Loop
    # ═════════════════════════════════════════════════════════════════════════
    def _update_preview_loop(self):
        if not self.running:
            return

        with self.receiver.frame_lock:
            rgb_frame = self.receiver.current_rgb_frame
            fps = self.receiver.fps_actual
            lat = self.receiver.latency_ms
            res = self.receiver.resolution_str
            kbps = self.receiver.bitrate_kbps

        if rgb_frame is not None:
            canvas_w = self.video_canvas.winfo_width()
            canvas_h = self.video_canvas.winfo_height()

            if canvas_w > 50 and canvas_h > 50:
                frame_h, frame_w, _ = rgb_frame.shape
                # Keep aspect ratio
                scale = min(canvas_w / frame_w, canvas_h / frame_h)
                new_w = int(frame_w * scale)
                new_h = int(frame_h * scale)

                img = Image.fromarray(rgb_frame)
                img = img.resize((new_w, new_h), Image.NEAREST)
                self._tk_img = ImageTk.PhotoImage(image=img)

                self.video_canvas.delete("all")
                self.video_canvas.create_image(canvas_w // 2, canvas_h // 2, anchor="center", image=self._tk_img)

            # Update live stats
            conn_type = "USB" if self.is_usb_active else "Wi-Fi"
            self.metrics_label.configure(
                text=f"● LIVE ({conn_type})  |  {fps:.1f} FPS  |  {lat} ms  |  {res}  |  {kbps:.0f} KB/s"
            )

        self.after(20, self._update_preview_loop)

    def _check_network_timeout(self):
        self.network.check_timeout()
        self.after(2000, self._check_network_timeout)

    # ═════════════════════════════════════════════════════════════════════════
    # Helpers
    # ═════════════════════════════════════════════════════════════════════════
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
        qr = qrcode.make(f"bonaycamera://{ip}")
        qr_path = os.path.join(os.path.dirname(__file__), "qr.png")
        qr.save(qr_path)
        img = ctk.CTkImage(light_image=Image.open(qr_path), size=(110, 110))
        self.qr_label.configure(image=img)

    def on_closing(self):
        self.running = False
        self.receiver.stop_servers()
        self.network.stop()
        self.destroy()

if __name__ == "__main__":
    app = BonayCameraDesktopApp()
    app.protocol("WM_DELETE_WINDOW", app.on_closing)
    app.mainloop()
