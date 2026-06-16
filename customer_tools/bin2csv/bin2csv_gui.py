from __future__ import annotations

import os
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from binary_log import convert_file, default_destination


class Bin2CsvApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("MotemaSens SD BIN to CSV")
        self.geometry("720x420")
        self.minsize(680, 390)

        self.source_var = tk.StringVar()
        self.destination_dir_var = tk.StringVar()
        self.output_name_var = tk.StringVar()
        self.overwrite_var = tk.BooleanVar(value=False)
        self.open_after_var = tk.BooleanVar(value=True)
        self.status_var = tk.StringVar(value="Pick an SD card .bin log and convert it to CSV.")

        self._build_ui()

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=16)
        root.pack(fill=tk.BOTH, expand=True)
        root.columnconfigure(1, weight=1)

        title = ttk.Label(root, text="MotemaSens SD card log converter", font=("Segoe UI", 14, "bold"))
        title.grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 10))

        ttk.Label(root, text="Input BIN").grid(row=1, column=0, sticky="w", pady=(0, 8))
        ttk.Entry(root, textvariable=self.source_var).grid(row=1, column=1, sticky="ew", padx=8, pady=(0, 8))
        ttk.Button(root, text="Browse", command=self._browse_source).grid(row=1, column=2, pady=(0, 8))

        ttk.Label(root, text="Output folder").grid(row=2, column=0, sticky="w", pady=(0, 8))
        ttk.Entry(root, textvariable=self.destination_dir_var).grid(row=2, column=1, sticky="ew", padx=8, pady=(0, 8))
        ttk.Button(root, text="Browse", command=self._browse_destination).grid(row=2, column=2, pady=(0, 8))

        ttk.Label(root, text="CSV filename").grid(row=3, column=0, sticky="w", pady=(0, 8))
        ttk.Entry(root, textvariable=self.output_name_var).grid(row=3, column=1, sticky="ew", padx=8, pady=(0, 8))
        ttk.Button(root, text="Use same name", command=self._use_same_name).grid(row=3, column=2, pady=(0, 8))

        options = ttk.Frame(root)
        options.grid(row=4, column=1, sticky="w", pady=(2, 12))
        ttk.Checkbutton(options, text="Overwrite existing CSV", variable=self.overwrite_var).grid(row=0, column=0, sticky="w")
        ttk.Checkbutton(options, text="Open CSV after convert", variable=self.open_after_var).grid(row=0, column=1, sticky="w", padx=(18, 0))

        ttk.Button(root, text="Convert to CSV", command=self._convert).grid(row=5, column=1, sticky="ew", padx=8, pady=(0, 10))

        ttk.Separator(root).grid(row=6, column=0, columnspan=3, sticky="ew", pady=8)

        ttk.Label(root, text="Status").grid(row=7, column=0, sticky="nw")
        status_box = tk.Text(root, height=8, wrap="word", bg="#0f141a", fg="#dce6f0", insertbackground="#dce6f0")
        status_box.grid(row=7, column=1, columnspan=2, sticky="nsew", padx=(8, 0))
        status_box.insert("end", "Ready.\n")
        status_box.configure(state="disabled")
        self.status_box = status_box

        root.rowconfigure(7, weight=1)

    def _log(self, message: str) -> None:
        self.status_var.set(message)
        self.status_box.configure(state="normal")
        self.status_box.insert("end", message + "\n")
        self.status_box.see("end")
        self.status_box.configure(state="disabled")

    def _browse_source(self) -> None:
        filename = filedialog.askopenfilename(
            title="Select MotemaSens SD binary log",
            filetypes=[("MotemaSens binary logs", "*.bin"), ("All files", "*.*")],
        )
        if not filename:
            return
        source = Path(filename)
        self.source_var.set(str(source))
        self.destination_dir_var.set(str(source.parent))
        self.output_name_var.set(default_destination(source).name)
        self._log(f"Selected {source.name}")

    def _browse_destination(self) -> None:
        folder = filedialog.askdirectory(title="Select output folder")
        if folder:
            self.destination_dir_var.set(folder)
            self._log(f"Output folder set to {folder}")

    def _use_same_name(self) -> None:
        source_text = self.source_var.get().strip()
        if not source_text:
            messagebox.showinfo("MotemaSens", "Pick the BIN file first.")
            return
        self.output_name_var.set(default_destination(Path(source_text)).name)

    def _resolve_destination(self, source: Path) -> Path:
        destination_dir_text = self.destination_dir_var.get().strip()
        destination_dir = Path(destination_dir_text) if destination_dir_text else source.parent
        output_name = self.output_name_var.get().strip()
        if not output_name:
            output_name = default_destination(source).name
        if Path(output_name).suffix.lower() != ".csv":
            output_name += ".csv"
        return destination_dir / output_name

    def _convert(self) -> None:
        try:
            source = Path(self.source_var.get().strip())
            if not source.exists():
                raise FileNotFoundError("Input BIN file not found")
            destination = self._resolve_destination(source)
            destination.parent.mkdir(parents=True, exist_ok=True)

            if destination.exists() and not self.overwrite_var.get():
                if not messagebox.askyesno("Overwrite CSV?", f"{destination.name} already exists.\nOverwrite it?"):
                    self._log("Conversion cancelled.")
                    return

            self._log(f"Converting {source.name} to {destination.name} ...")
            rows = convert_file(source, destination, overwrite=True)
            self._log(f"Done. Wrote {rows} rows to {destination}")
            messagebox.showinfo("MotemaSens", f"Converted {rows} rows.\n\n{destination}")

            if self.open_after_var.get():
                try:
                    os.startfile(destination)
                except Exception:
                    pass
        except Exception as exc:  # noqa: BLE001 - user-facing tool.
            self._log(f"Conversion failed: {exc}")
            messagebox.showerror("Conversion failed", str(exc))


def main() -> int:
    app = Bin2CsvApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
