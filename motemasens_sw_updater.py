"""Customer firmware updater for MotemaSens ESP32 devices.

This tool intentionally only flashes released binary images from the public
MotemaSens-SW repository. It does not contain firmware source or factory
serial-number provisioning controls.
"""

from __future__ import annotations

import hashlib
import json
import os
import queue
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from tkinter import DISABLED, NORMAL, BooleanVar, StringVar, Text, Tk, messagebox
from tkinter import ttk

try:
    from serial.tools import list_ports
except Exception as exc:  # pragma: no cover - shown in the GUI at runtime
    list_ports = None
    SERIAL_IMPORT_ERROR = exc
else:
    SERIAL_IMPORT_ERROR = None


PUBLIC_RAW_BASE = "https://raw.githubusercontent.com/mmarzook3/MotemaSens-SW/main"
MANIFEST_URL = f"{PUBLIC_RAW_BASE}/manifest.json"
APP_TITLE = "MotemaSens SW Updater"
CACHE_DIR = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "MotemaSens" / "SWUpdater"


@dataclass(frozen=True)
class FirmwareFile:
    key: str
    address: str
    path: str
    url: str
    sha256: str
    size: int


@dataclass(frozen=True)
class FirmwareVersion:
    version: str
    name: str
    firmware_version: str
    source_commit: str
    release_date: str
    notes: str
    files: tuple[FirmwareFile, ...]

    @property
    def label(self) -> str:
        return f"{self.version} - {self.name}"


class UpdaterApp:
    def __init__(self, root: Tk) -> None:
        self.root = root
        self.root.title(APP_TITLE)
        self.root.geometry("820x620")
        self.root.minsize(760, 560)

        self.log_queue: queue.Queue[str] = queue.Queue()
        self.versions: list[FirmwareVersion] = []
        self.version_by_label: dict[str, FirmwareVersion] = {}

        self.port_var = StringVar()
        self.version_var = StringVar()
        self.status_var = StringVar(value="Ready")
        self.erase_var = BooleanVar(value=False)

        self._build_ui()
        self._poll_log_queue()
        self.refresh_ports()
        self.refresh_versions_async()

    def _build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=14)
        outer.pack(fill="both", expand=True)
        outer.columnconfigure(0, weight=1)
        outer.rowconfigure(4, weight=1)

        header = ttk.Frame(outer)
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(0, weight=1)
        ttk.Label(header, text=APP_TITLE, font=("Segoe UI", 18, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(header, text="Flash released MotemaSens firmware from the public SW repository.").grid(
            row=1, column=0, sticky="w", pady=(2, 10)
        )

        body = ttk.LabelFrame(outer, text="Update setup", padding=12)
        body.grid(row=1, column=0, sticky="ew", pady=(0, 10))
        body.columnconfigure(1, weight=1)

        ttk.Label(body, text="Firmware version").grid(row=0, column=0, sticky="w", padx=(0, 10), pady=5)
        self.version_combo = ttk.Combobox(body, textvariable=self.version_var, state="readonly")
        self.version_combo.grid(row=0, column=1, sticky="ew", pady=5)
        self.version_combo.bind("<<ComboboxSelected>>", lambda _event: self.show_selected_version())
        ttk.Button(body, text="Refresh versions", command=self.refresh_versions_async).grid(
            row=0, column=2, sticky="ew", padx=(10, 0), pady=5
        )

        ttk.Label(body, text="USB COM port").grid(row=1, column=0, sticky="w", padx=(0, 10), pady=5)
        self.port_combo = ttk.Combobox(body, textvariable=self.port_var, state="readonly")
        self.port_combo.grid(row=1, column=1, sticky="ew", pady=5)
        ttk.Button(body, text="Refresh ports", command=self.refresh_ports).grid(
            row=1, column=2, sticky="ew", padx=(10, 0), pady=5
        )

        options = ttk.Frame(body)
        options.grid(row=2, column=1, sticky="w", pady=(6, 0))
        ttk.Checkbutton(options, text="Erase flash before update", variable=self.erase_var).pack(side="left")

        actions = ttk.Frame(outer)
        actions.grid(row=2, column=0, sticky="ew", pady=(0, 8))
        self.flash_button = ttk.Button(actions, text="Flash selected version", command=self.flash_selected_async)
        self.flash_button.pack(side="left")
        ttk.Button(actions, text="Open cache folder", command=self.open_cache_folder).pack(side="left", padx=(10, 0))

        self.status_label = ttk.Label(outer, textvariable=self.status_var)
        self.status_label.grid(row=3, column=0, sticky="ew", pady=(0, 8))

        log_frame = ttk.LabelFrame(outer, text="Log", padding=8)
        log_frame.grid(row=4, column=0, sticky="nsew")
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)
        self.log_text = Text(log_frame, wrap="word", height=18)
        self.log_text.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(log_frame, command=self.log_text.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.log_text.configure(yscrollcommand=scroll.set)

    def log(self, message: str) -> None:
        timestamp = time.strftime("%H:%M:%S")
        self.log_queue.put(f"[{timestamp}] {message}\n")

    def _poll_log_queue(self) -> None:
        while True:
            try:
                message = self.log_queue.get_nowait()
            except queue.Empty:
                break
            self.log_text.insert("end", message)
            self.log_text.see("end")
        self.root.after(100, self._poll_log_queue)

    def set_busy(self, busy: bool, status: str) -> None:
        if threading.current_thread() is not threading.main_thread():
            self.root.after(0, self.set_busy, busy, status)
            return
        self.status_var.set(status)
        self.flash_button.configure(state=DISABLED if busy else NORMAL)

    def refresh_ports(self) -> None:
        if SERIAL_IMPORT_ERROR is not None or list_ports is None:
            self.log(f"pyserial is not available: {SERIAL_IMPORT_ERROR}")
            messagebox.showwarning(
                "Missing pyserial",
                "pyserial is not available. Run the BAT file so prerequisites are installed.",
            )
            return

        ports = []
        preferred_words = ("ch340", "uart", "cp210", "silicon", "espressif")
        port_rows = []
        for port in list_ports.comports():
            label = f"{port.device} - {port.description}"
            text = label.lower()
            if "usb-enhanced-serial ch343" in text:
                priority = 0
            elif "ch343" in text:
                priority = 1
            elif "usb" in text and any(word in text for word in preferred_words):
                priority = 2
            elif "usb" in text:
                priority = 3
            elif "bluetooth" in text:
                priority = 5
            else:
                priority = 4
            port_rows.append((priority, port.device, label))

        port_rows.sort(key=lambda item: (item[0], item[1]))
        ports = [item[2] for item in port_rows]

        self.port_combo["values"] = ports
        if ports:
            self.port_combo.current(0)
            self.log(f"Found {len(ports)} serial port(s). Auto-selected {ports[0]}.")
        else:
            self.port_var.set("")
            self.log("No serial ports found. Connect the device over USB and click Refresh ports.")

    def refresh_versions_async(self) -> None:
        thread = threading.Thread(target=self.refresh_versions, daemon=True)
        thread.start()

    def refresh_versions(self) -> None:
        try:
            self.set_busy(True, "Downloading release list...")
            self.log(f"Downloading manifest: {MANIFEST_URL}")
            manifest = download_json(MANIFEST_URL)
            versions = parse_versions(manifest)
            if not versions:
                raise RuntimeError("No firmware versions are listed in the public manifest.")
            self.versions = versions
            self.version_by_label = {item.label: item for item in versions}
            labels = [item.label for item in versions]
            self.root.after(0, self._apply_versions, labels, manifest.get("latest", versions[0].version))
            self.log(f"Found {len(versions)} released version(s).")
        except Exception as exc:
            self.log(f"Version refresh failed: {exc}")
            self.root.after(0, messagebox.showerror, "Version refresh failed", str(exc))
        finally:
            self.set_busy(False, "Ready")

    def _apply_versions(self, labels: list[str], latest: str) -> None:
        self.version_combo["values"] = labels
        selected = 0
        for index, label in enumerate(labels):
            if self.version_by_label[label].version == latest:
                selected = index
                break
        self.version_combo.current(selected)
        self.show_selected_version()

    def selected_version(self) -> FirmwareVersion:
        label = self.version_var.get()
        version = self.version_by_label.get(label)
        if not version:
            raise RuntimeError("Select a firmware version first.")
        return version

    def selected_port(self) -> str:
        label = self.port_var.get().strip()
        if not label:
            raise RuntimeError("Select a USB COM port first.")
        return label.split(" - ", 1)[0].strip()

    def show_selected_version(self) -> None:
        try:
            version = self.selected_version()
        except RuntimeError:
            return
        self.log(
            f"Selected {version.version}: firmware={version.firmware_version}, "
            f"source={version.source_commit[:12]}, date={version.release_date}"
        )
        if version.notes:
            self.log(f"Notes: {version.notes}")

    def open_cache_folder(self) -> None:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        os.startfile(str(CACHE_DIR))  # type: ignore[attr-defined]

    def flash_selected_async(self) -> None:
        thread = threading.Thread(target=self.flash_selected, daemon=True)
        thread.start()

    def flash_selected(self) -> None:
        try:
            version = self.selected_version()
            port = self.selected_port()
            self.set_busy(True, f"Preparing {version.version}...")
            release_dir = CACHE_DIR / "versions" / version.version
            release_dir.mkdir(parents=True, exist_ok=True)

            local_files: dict[str, Path] = {}
            for firmware_file in version.files:
                local_path = release_dir / Path(firmware_file.path).name
                self.download_and_verify(firmware_file, local_path)
                local_files[firmware_file.key] = local_path

            self.set_busy(True, f"Flashing {version.version} on {port}...")
            if self.erase_var.get():
                self.run_esptool([sys.executable, "-m", "esptool", "--chip", "esp32s3", "--port", port, "erase_flash"])

            command = [
                sys.executable,
                "-m",
                "esptool",
                "--chip",
                "esp32s3",
                "--port",
                port,
                "--baud",
                "921600",
                "--before",
                "default_reset",
                "--after",
                "hard_reset",
                "write_flash",
                "-z",
            ]
            for firmware_file in version.files:
                command.extend([firmware_file.address, str(local_files[firmware_file.key])])
            self.run_esptool(command)
            self.log("Flash completed. The device should restart now.")
            self.root.after(0, messagebox.showinfo, "Flash complete", f"{version.version} was flashed successfully.")
        except Exception as exc:
            self.log(f"Flash failed: {exc}")
            self.root.after(0, messagebox.showerror, "Flash failed", str(exc))
        finally:
            self.set_busy(False, "Ready")

    def download_and_verify(self, firmware_file: FirmwareFile, local_path: Path) -> None:
        if local_path.exists() and sha256_file(local_path).lower() == firmware_file.sha256.lower():
            self.log(f"Using cached {firmware_file.key}: {local_path}")
            return
        self.log(f"Downloading {firmware_file.key}: {firmware_file.url}")
        data = download_bytes(firmware_file.url)
        actual = hashlib.sha256(data).hexdigest()
        if actual.lower() != firmware_file.sha256.lower():
            raise RuntimeError(
                f"Checksum failed for {firmware_file.key}: expected {firmware_file.sha256}, got {actual}"
            )
        if firmware_file.size and len(data) != firmware_file.size:
            raise RuntimeError(
                f"Size failed for {firmware_file.key}: expected {firmware_file.size}, got {len(data)}"
            )
        local_path.write_bytes(data)
        self.log(f"Saved {firmware_file.key}: {local_path}")

    def run_esptool(self, command: list[str]) -> None:
        self.log("Running: " + " ".join(command))
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        assert process.stdout is not None
        for line in process.stdout:
            self.log(line.rstrip())
        exit_code = process.wait()
        if exit_code != 0:
            raise RuntimeError(f"esptool failed with exit code {exit_code}")


def download_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "MotemaSens-SW-Updater"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Could not download {url}: {exc}") from exc


def download_json(url: str) -> dict:
    return json.loads(download_bytes(url).decode("utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_versions(manifest: dict) -> list[FirmwareVersion]:
    versions: list[FirmwareVersion] = []
    for item in manifest.get("versions", []):
        files = []
        for key, file_item in item.get("files", {}).items():
            files.append(
                FirmwareFile(
                    key=key,
                    address=str(file_item["address"]),
                    path=str(file_item["path"]),
                    url=str(file_item.get("url") or f"{PUBLIC_RAW_BASE}/{file_item['path']}"),
                    sha256=str(file_item["sha256"]),
                    size=int(file_item.get("size", 0)),
                )
            )
        files.sort(key=lambda entry: int(entry.address, 16))
        versions.append(
            FirmwareVersion(
                version=str(item["version"]),
                name=str(item.get("name", item["version"])),
                firmware_version=str(item.get("firmware_version", "")),
                source_commit=str(item.get("source_commit", "")),
                release_date=str(item.get("release_date", "")),
                notes=str(item.get("notes", "")),
                files=tuple(files),
            )
        )
    return versions


def main() -> int:
    root = Tk()
    try:
        style = ttk.Style(root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
    except Exception:
        pass
    UpdaterApp(root)
    root.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
