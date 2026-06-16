"""MotemaSens USB logger and user utility.

This tool connects to the ESP32 USB serial port, controls the firmware USB
live logger, saves CSV rows, shows a small live status view, and also exposes
the SD BIN to CSV converter in the same user app.
"""

from __future__ import annotations

import csv
import os
import queue
import re
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from tkinter import BooleanVar, StringVar, Text, Tk, filedialog, messagebox
from tkinter import ttk
import tkinter as tk

try:
    import serial
    from serial.tools import list_ports
except Exception as exc:  # pragma: no cover - shown in GUI at runtime.
    serial = None
    list_ports = None
    SERIAL_IMPORT_ERROR = exc
else:
    SERIAL_IMPORT_ERROR = None


TOOL_DIR = Path(__file__).resolve().parent
BIN2CSV_DIR = TOOL_DIR.parent / "bin2csv"
if str(BIN2CSV_DIR) not in sys.path:
    sys.path.insert(0, str(BIN2CSV_DIR))

try:
    from binary_log import convert_file, default_destination
except Exception as exc:  # pragma: no cover - shown in GUI at runtime.
    convert_file = None
    default_destination = None
    BIN2CSV_IMPORT_ERROR = exc
else:
    BIN2CSV_IMPORT_ERROR = None


APP_TITLE = "MotemaSens USB Logger"
DEFAULT_BAUD = "115200"
BAUD_OPTIONS = ("115200", "921600", "460800", "230400")
CSV_HEADER_PREFIX = "LOG_HEADER,"
CSV_ROW_PREFIX = "LOG,"
BEAT_PREFIX = "BEAT,"
START_PREFIX = "LIVE_TEST_START"
END_PREFIX = "LIVE_TEST_END"


@dataclass(frozen=True)
class PortInfo:
    device: str
    description: str
    hwid: str

    @property
    def label(self) -> str:
        return f"{self.device} - {self.description}"


class SerialWorker(threading.Thread):
    def __init__(
        self,
        port: str,
        baud: int,
        out_queue: "queue.Queue[tuple[str, str]]",
        stop_event: threading.Event,
    ) -> None:
        super().__init__(daemon=True)
        self.port = port
        self.baud = baud
        self.out_queue = out_queue
        self.stop_event = stop_event
        self.serial_port = None
        self.write_lock = threading.Lock()

    def run(self) -> None:
        if serial is None:
            self.out_queue.put(("error", f"pyserial is not available: {SERIAL_IMPORT_ERROR}"))
            return
        try:
            self.serial_port = serial.Serial(self.port, self.baud, timeout=0.15, write_timeout=1.0)
            self.serial_port.reset_input_buffer()
            self.out_queue.put(("connected", f"Connected to {self.port} at {self.baud} baud"))
            buffer = bytearray()
            while not self.stop_event.is_set():
                data = self.serial_port.read(256)
                if not data:
                    continue
                for byte in data:
                    if byte in (10, 13):
                        if buffer:
                            line = buffer.decode("utf-8", errors="replace").strip()
                            buffer.clear()
                            if line:
                                self.out_queue.put(("line", line))
                    else:
                        buffer.append(byte)
                        if len(buffer) > 4096:
                            line = buffer.decode("utf-8", errors="replace").strip()
                            buffer.clear()
                            self.out_queue.put(("line", line))
        except Exception as exc:  # noqa: BLE001 - user-facing tool.
            self.out_queue.put(("error", f"Serial error: {exc}"))
        finally:
            try:
                if self.serial_port and self.serial_port.is_open:
                    self.serial_port.close()
            except Exception:
                pass
            self.out_queue.put(("disconnected", "USB serial disconnected"))

    def write(self, text: str) -> None:
        with self.write_lock:
            if not self.serial_port or not self.serial_port.is_open:
                raise RuntimeError("Serial port is not connected")
            self.serial_port.write(text.encode("ascii", errors="ignore"))
            self.serial_port.flush()


class UsbLoggerApp(Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_TITLE)
        self.geometry("1080x720")
        self.minsize(960, 640)

        self.style = ttk.Style(self)
        self._setup_style()

        self.serial_queue: "queue.Queue[tuple[str, str]]" = queue.Queue()
        self.stop_event = threading.Event()
        self.worker: SerialWorker | None = None
        self.ports_by_label: dict[str, PortInfo] = {}

        self.port_var = StringVar()
        self.baud_var = StringVar(value=DEFAULT_BAUD)
        self.output_dir_var = StringVar(value=str(Path.home() / "Documents" / "MotemaSens"))
        self.filename_var = StringVar(value=self._default_capture_name())
        self.raw_log_var = BooleanVar(value=True)
        self.open_after_var = BooleanVar(value=False)
        self.status_var = StringVar(value="Ready")
        self.connection_var = StringVar(value="Disconnected")
        self.capture_var = StringVar(value="Idle")
        self.version_var = StringVar(value="-")
        self.serial_var = StringVar(value="-")
        self.ip_var = StringVar(value="-")
        self.row_rate_var = StringVar(value="0.0 Hz")
        self.rows_var = StringVar(value="0")
        self.beats_var = StringVar(value="0")
        self.bpm_var = StringVar(value="-")
        self.elapsed_var = StringVar(value="0.0 s")
        self.last_ecg_var = StringVar(value="-")

        self.capture_active = False
        self.capture_start_time = 0.0
        self.rows_written = 0
        self.beats_seen = 0
        self.csv_file = None
        self.raw_file = None
        self.csv_writer: csv.writer | None = None
        self.current_header: list[str] = []
        self.last_rate_time = time.monotonic()
        self.last_rate_rows = 0
        self.mic_samples: list[float] = []
        self.ecg_samples: list[float] = []

        self._build_ui()
        self._poll_serial_queue()
        self._tick_status()
        self.refresh_ports()

    def _setup_style(self) -> None:
        self.style.theme_use("clam")
        self.style.configure("TFrame", background="#f5f7fb")
        self.style.configure("Card.TFrame", background="#ffffff", relief="flat")
        self.style.configure("TLabel", background="#f5f7fb", foreground="#172033", font=("Segoe UI", 9))
        self.style.configure("Card.TLabel", background="#ffffff", foreground="#172033", font=("Segoe UI", 8))
        self.style.configure("Title.TLabel", background="#f5f7fb", foreground="#0b2545", font=("Segoe UI", 18, "bold"))
        self.style.configure("Section.TLabel", background="#ffffff", foreground="#0f766e", font=("Segoe UI", 11, "bold"))
        self.style.configure("Value.TLabel", background="#ffffff", foreground="#0b2545", font=("Segoe UI", 10, "bold"))
        self.style.configure("Good.TLabel", background="#ffffff", foreground="#15803d", font=("Segoe UI", 10, "bold"))
        self.style.configure("Bad.TLabel", background="#ffffff", foreground="#dc2626", font=("Segoe UI", 10, "bold"))
        self.style.configure("Accent.TButton", font=("Segoe UI", 9, "bold"))

    def _build_ui(self) -> None:
        outer = ttk.Frame(self, padding=14)
        outer.pack(fill="both", expand=True)
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(1, weight=1)

        ttk.Label(outer, text=APP_TITLE, style="Title.TLabel").grid(row=0, column=0, sticky="w")
        self.notebook = ttk.Notebook(outer)
        self.notebook.grid(row=1, column=0, sticky="nsew", pady=(12, 0))

        self.usb_tab = ttk.Frame(self.notebook, padding=12)
        self.converter_tab = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(self.usb_tab, text="USB logging")
        self.notebook.add(self.converter_tab, text="BIN to CSV")
        self._build_usb_tab()
        self._build_converter_tab()

    def _build_usb_tab(self) -> None:
        tab = self.usb_tab
        tab.columnconfigure(0, weight=1)
        tab.columnconfigure(1, weight=1)
        tab.rowconfigure(2, weight=1)

        setup = ttk.LabelFrame(tab, text="USB connection and capture", padding=12)
        setup.grid(row=0, column=0, columnspan=2, sticky="ew")
        setup.columnconfigure(1, weight=1)
        setup.columnconfigure(4, weight=1)

        ttk.Label(setup, text="USB COM port").grid(row=0, column=0, sticky="w", padx=(0, 8), pady=4)
        self.port_combo = ttk.Combobox(setup, textvariable=self.port_var, state="readonly")
        self.port_combo.grid(row=0, column=1, sticky="ew", pady=4)
        ttk.Button(setup, text="Refresh", command=self.refresh_ports).grid(row=0, column=2, sticky="ew", padx=8, pady=4)
        ttk.Label(setup, text="Baud").grid(row=0, column=3, sticky="w", padx=(10, 8), pady=4)
        ttk.Combobox(setup, textvariable=self.baud_var, values=BAUD_OPTIONS, width=12).grid(
            row=0, column=4, sticky="w", pady=4
        )

        ttk.Label(setup, text="Output folder").grid(row=1, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(setup, textvariable=self.output_dir_var).grid(row=1, column=1, columnspan=4, sticky="ew", pady=4)
        ttk.Button(setup, text="Browse", command=self._browse_output_dir).grid(row=1, column=5, padx=(8, 0), pady=4)

        ttk.Label(setup, text="CSV filename").grid(row=2, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(setup, textvariable=self.filename_var).grid(row=2, column=1, columnspan=4, sticky="ew", pady=4)
        ttk.Button(setup, text="New name", command=lambda: self.filename_var.set(self._default_capture_name())).grid(
            row=2, column=5, padx=(8, 0), pady=4
        )

        options = ttk.Frame(setup)
        options.grid(row=3, column=1, columnspan=5, sticky="w", pady=(4, 0))
        ttk.Checkbutton(options, text="Save raw serial .txt beside CSV", variable=self.raw_log_var).pack(side="left")
        ttk.Checkbutton(options, text="Open CSV after stop", variable=self.open_after_var).pack(side="left", padx=(20, 0))

        buttons = ttk.Frame(tab)
        buttons.grid(row=1, column=0, columnspan=2, sticky="ew", pady=10)
        for index in range(7):
            buttons.columnconfigure(index, weight=1)
        self.connect_button = ttk.Button(buttons, text="Connect", command=self.connect_serial, style="Accent.TButton")
        self.connect_button.grid(row=0, column=0, sticky="ew", padx=(0, 6))
        self.disconnect_button = ttk.Button(buttons, text="Close", command=self.disconnect_serial)
        self.disconnect_button.grid(row=0, column=1, sticky="ew", padx=6)
        self.start_button = ttk.Button(buttons, text="Start log", command=self.start_usb_log, style="Accent.TButton")
        self.start_button.grid(row=0, column=2, sticky="ew", padx=6)
        self.stop_button = ttk.Button(buttons, text="Stop log", command=self.stop_usb_log)
        self.stop_button.grid(row=0, column=3, sticky="ew", padx=6)
        ttk.Button(buttons, text="Device ID", command=self.query_device).grid(row=0, column=4, sticky="ew", padx=6)
        ttk.Button(buttons, text="Clear", command=self.clear_log_view).grid(row=0, column=5, sticky="ew", padx=6)
        ttk.Button(buttons, text="Folder", command=self.open_output_folder).grid(row=0, column=6, sticky="ew", padx=(6, 0))

        left = ttk.Frame(tab)
        left.grid(row=2, column=0, sticky="nsew", padx=(0, 8))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(1, weight=1)

        status_card = ttk.Frame(left, style="Card.TFrame", padding=10)
        status_card.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        status_card.columnconfigure(0, weight=0)
        status_card.columnconfigure(1, weight=1)
        status_card.columnconfigure(2, weight=0)
        status_card.columnconfigure(3, weight=1)
        ttk.Label(status_card, text="Live status", style="Section.TLabel").grid(row=0, column=0, columnspan=4, sticky="w")
        status_rows = [
            ("Connection", self.connection_var),
            ("Capture", self.capture_var),
            ("Device version", self.version_var),
            ("Serial", self.serial_var),
            ("IP", self.ip_var),
            ("Rows", self.rows_var),
            ("Row rate", self.row_rate_var),
            ("Elapsed", self.elapsed_var),
            ("Beats", self.beats_var),
            ("BPM", self.bpm_var),
            ("ECG status", self.last_ecg_var),
        ]
        for index, (label, variable) in enumerate(status_rows, 1):
            col = 0 if index <= 6 else 2
            row = index if index <= 6 else index - 6
            ttk.Label(status_card, text=f"{label}:", style="Card.TLabel").grid(row=row, column=col, sticky="w", pady=2)
            ttk.Label(status_card, textvariable=variable, style="Value.TLabel", wraplength=135).grid(
                row=row, column=col + 1, sticky="ew", padx=(6, 14), pady=2
            )

        plot_card = ttk.Frame(left, style="Card.TFrame", padding=12)
        plot_card.grid(row=1, column=0, sticky="nsew")
        plot_card.columnconfigure(0, weight=1)
        plot_card.rowconfigure(1, weight=1)
        ttk.Label(plot_card, text="Live USB preview", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        self.canvas = tk.Canvas(plot_card, height=260, bg="#071015", highlightthickness=0)
        self.canvas.grid(row=1, column=0, sticky="nsew", pady=(8, 0))

        right = ttk.Frame(tab)
        right.grid(row=2, column=1, sticky="nsew", padx=(8, 0))
        right.columnconfigure(0, weight=1)
        right.rowconfigure(0, weight=1)
        log_card = ttk.Frame(right, style="Card.TFrame", padding=12)
        log_card.grid(row=0, column=0, sticky="nsew")
        log_card.columnconfigure(0, weight=1)
        log_card.rowconfigure(1, weight=1)
        ttk.Label(log_card, text="USB serial view", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        self.log_text = Text(log_card, wrap="none", height=18, bg="#071015", fg="#dbeafe", insertbackground="#dbeafe")
        self.log_text.grid(row=1, column=0, sticky="nsew", pady=(8, 0))
        scroll_y = ttk.Scrollbar(log_card, command=self.log_text.yview)
        scroll_y.grid(row=1, column=1, sticky="ns", pady=(8, 0))
        self.log_text.configure(yscrollcommand=scroll_y.set)

        ttk.Label(tab, textvariable=self.status_var).grid(row=3, column=0, columnspan=2, sticky="ew", pady=(8, 0))

    def _build_converter_tab(self) -> None:
        tab = self.converter_tab
        tab.columnconfigure(1, weight=1)
        tab.rowconfigure(7, weight=1)
        self.bin_source_var = StringVar()
        self.bin_dest_dir_var = StringVar()
        self.bin_output_var = StringVar()
        self.bin_overwrite_var = BooleanVar(value=False)
        self.bin_open_var = BooleanVar(value=True)

        ttk.Label(tab, text="SD binary log converter", style="Title.TLabel").grid(
            row=0, column=0, columnspan=3, sticky="w", pady=(0, 12)
        )
        ttk.Label(tab, text="Input BIN").grid(row=1, column=0, sticky="w", pady=5)
        ttk.Entry(tab, textvariable=self.bin_source_var).grid(row=1, column=1, sticky="ew", padx=8, pady=5)
        ttk.Button(tab, text="Browse", command=self._browse_bin_source).grid(row=1, column=2, pady=5)

        ttk.Label(tab, text="Output folder").grid(row=2, column=0, sticky="w", pady=5)
        ttk.Entry(tab, textvariable=self.bin_dest_dir_var).grid(row=2, column=1, sticky="ew", padx=8, pady=5)
        ttk.Button(tab, text="Browse", command=self._browse_bin_dest).grid(row=2, column=2, pady=5)

        ttk.Label(tab, text="CSV filename").grid(row=3, column=0, sticky="w", pady=5)
        ttk.Entry(tab, textvariable=self.bin_output_var).grid(row=3, column=1, sticky="ew", padx=8, pady=5)
        ttk.Button(tab, text="Use same name", command=self._bin_use_same_name).grid(row=3, column=2, pady=5)

        opts = ttk.Frame(tab)
        opts.grid(row=4, column=1, sticky="w", pady=8)
        ttk.Checkbutton(opts, text="Overwrite existing CSV", variable=self.bin_overwrite_var).pack(side="left")
        ttk.Checkbutton(opts, text="Open CSV after convert", variable=self.bin_open_var).pack(side="left", padx=(20, 0))

        ttk.Button(tab, text="Convert BIN to CSV", command=self.convert_bin_to_csv, style="Accent.TButton").grid(
            row=5, column=1, sticky="ew", padx=8, pady=(0, 12)
        )
        ttk.Separator(tab).grid(row=6, column=0, columnspan=3, sticky="ew", pady=8)
        self.converter_log = Text(tab, height=12, wrap="word", bg="#071015", fg="#dbeafe", insertbackground="#dbeafe")
        self.converter_log.grid(row=7, column=0, columnspan=3, sticky="nsew")
        self._converter_log("Ready. Pick a MotemaSens SD .bin file and convert it to CSV.")

    def refresh_ports(self) -> None:
        if list_ports is None:
            messagebox.showerror("pyserial missing", f"pyserial is not available:\n{SERIAL_IMPORT_ERROR}")
            return
        found = [PortInfo(p.device, p.description or "Serial port", p.hwid or "") for p in list_ports.comports()]
        preferred = []
        other = []
        for port in found:
            text = f"{port.device} {port.description} {port.hwid}".lower()
            if any(word in text for word in ("ch343", "ch340", "usb-enhanced", "cp210", "espressif", "uart")):
                preferred.append(port)
            else:
                other.append(port)
        ordered = sorted(preferred, key=lambda p: p.device) + sorted(other, key=lambda p: p.device)
        self.ports_by_label = {port.label: port for port in ordered}
        labels = list(self.ports_by_label)
        self.port_combo.configure(values=labels)
        if labels and (not self.port_var.get() or self.port_var.get() not in labels):
            self.port_var.set(labels[0])
        self._set_status(f"Found {len(labels)} serial port(s). ESP32 style ports are shown first.")

    def connect_serial(self) -> None:
        if self.worker is not None:
            self._set_status("Already connected.")
            return
        label = self.port_var.get()
        port = self.ports_by_label.get(label)
        if not port:
            messagebox.showwarning("No port selected", "Select a USB COM port first.")
            return
        try:
            baud = int(self.baud_var.get().strip())
        except ValueError:
            messagebox.showerror("Bad baud", "Baud rate must be a number.")
            return
        self.stop_event.clear()
        self.worker = SerialWorker(port.device, baud, self.serial_queue, self.stop_event)
        self.worker.start()
        self.connection_var.set("Connecting")
        self._set_status(f"Connecting to {port.device} ...")

    def disconnect_serial(self) -> None:
        if self.capture_active:
            self.stop_usb_log()
        if self.worker is not None:
            self.stop_event.set()
            self.worker = None
        self.connection_var.set("Disconnected")
        self._set_status("Disconnect requested.")

    def start_usb_log(self) -> None:
        if self.worker is None:
            messagebox.showwarning("Not connected", "Connect to the ESP32 USB port first.")
            return
        self._open_capture_files()
        self._send_serial("S")
        self.capture_active = True
        self.capture_start_time = time.monotonic()
        self.rows_written = 0
        self.beats_seen = 0
        self.rows_var.set("0")
        self.beats_var.set("0")
        self.row_rate_var.set("0.0 Hz")
        self.capture_var.set("Starting")
        self.last_rate_time = time.monotonic()
        self.last_rate_rows = 0
        self.mic_samples.clear()
        self.ecg_samples.clear()
        self._set_status("USB logging requested. Waiting for LIVE_TEST_START and LOG rows.")

    def stop_usb_log(self) -> None:
        if self.worker is not None:
            try:
                self._send_serial("X")
            except Exception as exc:  # noqa: BLE001
                self._append_log(f"Stop command failed: {exc}")
        self.capture_var.set("Stopping")
        self._set_status("USB stop requested. Capture closes when LIVE_TEST_END is seen, or immediately if already idle.")
        if not self.capture_active:
            self._close_capture_files(open_after=False)

    def query_device(self) -> None:
        self._send_serial("DEVICE_SERIAL?\n")

    def _send_serial(self, text: str) -> None:
        if self.worker is None:
            messagebox.showwarning("Not connected", "Connect to a COM port first.")
            return
        try:
            self.worker.write(text)
            shown = text.replace("\n", "\\n").replace("\r", "\\r")
            self._append_log(f"> {shown}")
        except Exception as exc:  # noqa: BLE001
            messagebox.showerror("USB command failed", str(exc))
            self._set_status(f"USB command failed: {exc}")

    def _poll_serial_queue(self) -> None:
        while True:
            try:
                kind, message = self.serial_queue.get_nowait()
            except queue.Empty:
                break
            if kind == "connected":
                self.connection_var.set("Connected")
                self._append_log(message)
                self._set_status(message)
                self.query_device()
            elif kind == "disconnected":
                self.connection_var.set("Disconnected")
                self._append_log(message)
                if self.capture_active:
                    self._close_capture_files(open_after=False)
                self.worker = None
            elif kind == "error":
                self.connection_var.set("Error")
                self._append_log(message)
                self._set_status(message)
                if self.capture_active:
                    self._close_capture_files(open_after=False)
            elif kind == "line":
                self._handle_line(message)
        self.after(50, self._poll_serial_queue)

    def _handle_line(self, line: str) -> None:
        self._append_log(line)
        if self.raw_file is not None:
            self.raw_file.write(line + "\n")
            self.raw_file.flush()

        if line.startswith("device version:"):
            self.version_var.set(line.split(":", 1)[1].strip())
        elif line.startswith("LIVE_TEST_START"):
            self.capture_var.set("Logging")
            version = self._extract_key(line, "version")
            if version:
                self.version_var.set(version)
        elif line.startswith("DEVICE_SERIAL,"):
            serial_value = self._extract_key(line, "serial")
            device_id = self._extract_key(line, "deviceId")
            if serial_value:
                self.serial_var.set(f"{serial_value} ({device_id})" if device_id else serial_value)
        elif "wifi logger ready:" in line:
            match = re.search(r"http://([0-9.]+)/?", line)
            if match:
                self.ip_var.set(match.group(1))
        elif line.startswith("wifi connected, ip="):
            self.ip_var.set(line.split("=", 1)[1].strip())
        elif line.startswith(CSV_HEADER_PREFIX):
            self.current_header = next(csv.reader([line]))
            if self.csv_writer is not None:
                self.csv_writer.writerow(self.current_header)
                self.csv_file.flush()
        elif line.startswith(CSV_ROW_PREFIX):
            self._handle_csv_row(line)
        elif line.startswith(BEAT_PREFIX):
            self.beats_seen += 1
            self.beats_var.set(str(self.beats_seen))
            bpm = self._extract_key(line, "bpm")
            if bpm:
                self.bpm_var.set(bpm)
        elif line.startswith(END_PREFIX):
            self.capture_var.set("Complete")
            self._close_capture_files(open_after=self.open_after_var.get())
            reason = self._extract_key(line, "reason")
            self._set_status(f"USB log ended{f' ({reason})' if reason else ''}.")

    def _handle_csv_row(self, line: str) -> None:
        try:
            row = next(csv.reader([line]))
        except Exception:
            return
        if self.csv_writer is not None:
            if not self.current_header:
                self.current_header = ["LOG_HEADER"] + [f"field_{i}" for i in range(1, len(row))]
                self.csv_writer.writerow(self.current_header)
            self.csv_writer.writerow(row)
            if self.rows_written % 25 == 0 and self.csv_file is not None:
                self.csv_file.flush()
        self.rows_written += 1
        self.rows_var.set(str(self.rows_written))
        self._update_from_row(row)

    def _update_from_row(self, row: list[str]) -> None:
        if not self.current_header or len(row) != len(self.current_header):
            return
        values = dict(zip(self.current_header, row))
        if "bpm" in values:
            self.bpm_var.set(values["bpm"])
        if "ecg_status" in values:
            self.last_ecg_var.set(values["ecg_status"])
        mic = self._safe_float(values.get("mic_trace"))
        ecg = self._safe_float(values.get("ecg_ch1"))
        if ecg is None:
            ecg = self._safe_float(values.get("lead_i_raw"))
        if mic is not None:
            self.mic_samples.append(mic)
            self.mic_samples = self.mic_samples[-240:]
        if ecg is not None:
            self.ecg_samples.append(ecg)
            self.ecg_samples = self.ecg_samples[-240:]
        self._draw_preview()

    def _draw_preview(self) -> None:
        canvas = self.canvas
        width = max(canvas.winfo_width(), 300)
        height = max(canvas.winfo_height(), 180)
        canvas.delete("all")
        canvas.create_rectangle(0, 0, width, height, fill="#071015", outline="")
        for i in range(1, 5):
            y = int(height * i / 5)
            canvas.create_line(0, y, width, y, fill="#18313b")
        for i in range(1, 8):
            x = int(width * i / 8)
            canvas.create_line(x, 0, x, height, fill="#10242d")
        canvas.create_text(12, 18, text="MIC", fill="#65d841", anchor="w", font=("Segoe UI", 10, "bold"))
        canvas.create_text(12, height // 2 + 18, text="ECG", fill="#38a8ff", anchor="w", font=("Segoe UI", 10, "bold"))
        self._plot_line(self.mic_samples, 0, height // 2 - 4, "#65d841")
        self._plot_line(self.ecg_samples, height // 2 + 6, height - 6, "#38a8ff")

    def _plot_line(self, samples: list[float], top: int, bottom: int, color: str) -> None:
        if len(samples) < 2:
            return
        height = bottom - top
        width = max(self.canvas.winfo_width(), 300)
        min_v = min(samples)
        max_v = max(samples)
        if abs(max_v - min_v) < 1e-9:
            min_v -= 1.0
            max_v += 1.0
        points: list[float] = []
        for i, value in enumerate(samples):
            x = width * i / max(1, len(samples) - 1)
            y = bottom - ((value - min_v) / (max_v - min_v)) * height
            points.extend([x, y])
        self.canvas.create_line(*points, fill=color, width=2, smooth=True)

    def _tick_status(self) -> None:
        if self.capture_active:
            elapsed = max(0.0, time.monotonic() - self.capture_start_time)
            self.elapsed_var.set(f"{elapsed:.1f} s")
            now = time.monotonic()
            dt = now - self.last_rate_time
            if dt >= 1.0:
                rows_delta = self.rows_written - self.last_rate_rows
                self.row_rate_var.set(f"{rows_delta / dt:.1f} Hz")
                self.last_rate_time = now
                self.last_rate_rows = self.rows_written
        self.after(250, self._tick_status)

    def _open_capture_files(self) -> None:
        self._close_capture_files(open_after=False)
        out_dir = Path(self.output_dir_var.get().strip() or ".")
        out_dir.mkdir(parents=True, exist_ok=True)
        filename = self.filename_var.get().strip() or self._default_capture_name()
        if Path(filename).suffix.lower() != ".csv":
            filename += ".csv"
        csv_path = out_dir / filename
        self.csv_file = csv_path.open("w", newline="", encoding="utf-8")
        self.csv_writer = csv.writer(self.csv_file)
        if self.raw_log_var.get():
            self.raw_file = csv_path.with_suffix(".serial.txt").open("w", encoding="utf-8")
        self.active_csv_path = csv_path
        self._append_log(f"Saving USB CSV to {csv_path}")

    def _close_capture_files(self, open_after: bool) -> None:
        csv_path = getattr(self, "active_csv_path", None)
        for handle in (self.csv_file, self.raw_file):
            try:
                if handle is not None:
                    handle.flush()
                    handle.close()
            except Exception:
                pass
        self.csv_file = None
        self.raw_file = None
        self.csv_writer = None
        self.capture_active = False
        if self.capture_var.get() not in ("Complete", "Disconnected"):
            self.capture_var.set("Idle")
        if csv_path:
            self._append_log(f"Capture saved: {csv_path}")
            if open_after:
                try:
                    os.startfile(csv_path)
                except Exception:
                    pass

    def _browse_output_dir(self) -> None:
        folder = filedialog.askdirectory(title="Select USB log output folder")
        if folder:
            self.output_dir_var.set(folder)

    def open_output_folder(self) -> None:
        folder = Path(self.output_dir_var.get().strip() or ".")
        folder.mkdir(parents=True, exist_ok=True)
        os.startfile(folder)

    def clear_log_view(self) -> None:
        self.log_text.delete("1.0", "end")

    def _append_log(self, message: str) -> None:
        timestamp = time.strftime("%H:%M:%S")
        self.log_text.insert("end", f"[{timestamp}] {message}\n")
        self.log_text.see("end")

    def _set_status(self, message: str) -> None:
        self.status_var.set(message)

    def _default_capture_name(self) -> str:
        return "motemasens_usb_" + time.strftime("%Y%m%d_%H%M%S") + ".csv"

    def _extract_key(self, line: str, key: str) -> str:
        match = re.search(rf"(?:^|,){re.escape(key)}=([^,]+)", line)
        return match.group(1).strip() if match else ""

    def _safe_float(self, value: str | None) -> float | None:
        if value is None or value == "":
            return None
        try:
            return float(value)
        except ValueError:
            return None

    def _browse_bin_source(self) -> None:
        filename = filedialog.askopenfilename(
            title="Select MotemaSens SD binary log",
            filetypes=[("MotemaSens binary logs", "*.bin"), ("All files", "*.*")],
        )
        if not filename:
            return
        source = Path(filename)
        self.bin_source_var.set(str(source))
        self.bin_dest_dir_var.set(str(source.parent))
        if default_destination:
            self.bin_output_var.set(default_destination(source).name)

    def _browse_bin_dest(self) -> None:
        folder = filedialog.askdirectory(title="Select CSV output folder")
        if folder:
            self.bin_dest_dir_var.set(folder)

    def _bin_use_same_name(self) -> None:
        if default_destination is None:
            return
        source_text = self.bin_source_var.get().strip()
        if not source_text:
            messagebox.showinfo("MotemaSens", "Pick the BIN file first.")
            return
        self.bin_output_var.set(default_destination(Path(source_text)).name)

    def convert_bin_to_csv(self) -> None:
        if convert_file is None:
            messagebox.showerror("Converter missing", f"BIN converter is not available:\n{BIN2CSV_IMPORT_ERROR}")
            return
        try:
            source = Path(self.bin_source_var.get().strip())
            if not source.exists():
                raise FileNotFoundError("Input BIN file not found")
            dest_dir = Path(self.bin_dest_dir_var.get().strip() or str(source.parent))
            dest_dir.mkdir(parents=True, exist_ok=True)
            output_name = self.bin_output_var.get().strip()
            if not output_name and default_destination:
                output_name = default_destination(source).name
            if Path(output_name).suffix.lower() != ".csv":
                output_name += ".csv"
            destination = dest_dir / output_name
            if destination.exists() and not self.bin_overwrite_var.get():
                if not messagebox.askyesno("Overwrite CSV?", f"{destination.name} already exists.\nOverwrite it?"):
                    self._converter_log("Conversion cancelled.")
                    return
            self._converter_log(f"Converting {source.name} to {destination.name} ...")
            rows = convert_file(source, destination, overwrite=True)
            self._converter_log(f"Done. Wrote {rows} rows to {destination}")
            messagebox.showinfo("MotemaSens", f"Converted {rows} rows.\n\n{destination}")
            if self.bin_open_var.get():
                try:
                    os.startfile(destination)
                except Exception:
                    pass
        except Exception as exc:  # noqa: BLE001
            self._converter_log(f"Conversion failed: {exc}")
            messagebox.showerror("Conversion failed", str(exc))

    def _converter_log(self, message: str) -> None:
        timestamp = time.strftime("%H:%M:%S")
        self.converter_log.insert("end", f"[{timestamp}] {message}\n")
        self.converter_log.see("end")

    def destroy(self) -> None:
        try:
            self.disconnect_serial()
        finally:
            super().destroy()


def main() -> int:
    app = UsbLoggerApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
