from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from binary_log import convert_file, default_destination, inspect_file

TOOLS_DIR = Path(__file__).resolve().parents[2]
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from motemasens_tool_versions import APP_VERSION


class Bin2CsvApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"MotemaSens BIN to CSV v{APP_VERSION}")
        self.geometry("640x320")
        self.minsize(600, 300)

        self.source_var = tk.StringVar()
        self.destination_dir_var = tk.StringVar()
        self.output_name_var = tk.StringVar()
        self.overwrite_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value="Select a MotemaSens .bin log file.")

        self._build_ui()

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=18)
        root.pack(fill=tk.BOTH, expand=True)
        root.columnconfigure(1, weight=1)

        ttk.Label(root, text="Input BIN file").grid(row=0, column=0, sticky="w", pady=(0, 8))
        ttk.Entry(root, textvariable=self.source_var).grid(row=0, column=1, sticky="ew", padx=8, pady=(0, 8))
        ttk.Button(root, text="Browse", command=self._browse_source).grid(row=0, column=2, pady=(0, 8))

        ttk.Label(root, text="Destination folder").grid(row=1, column=0, sticky="w", pady=(0, 8))
        ttk.Entry(root, textvariable=self.destination_dir_var).grid(row=1, column=1, sticky="ew", padx=8, pady=(0, 8))
        ttk.Button(root, text="Browse", command=self._browse_destination).grid(row=1, column=2, pady=(0, 8))

        ttk.Label(root, text="CSV filename").grid(row=2, column=0, sticky="w", pady=(0, 8))
        ttk.Entry(root, textvariable=self.output_name_var).grid(row=2, column=1, sticky="ew", padx=8, pady=(0, 8))
        ttk.Button(root, text="Same name", command=self._use_same_name).grid(row=2, column=2, pady=(0, 8))

        ttk.Checkbutton(root, text="Overwrite existing CSV", variable=self.overwrite_var).grid(
            row=3, column=1, sticky="w", pady=(2, 14)
        )

        convert_button = ttk.Button(root, text="Convert to CSV", command=self._convert)
        convert_button.grid(row=4, column=1, sticky="ew", padx=8, pady=(0, 14))

        ttk.Separator(root).grid(row=5, column=0, columnspan=3, sticky="ew", pady=8)
        ttk.Label(root, textvariable=self.status_var, wraplength=560).grid(
            row=6, column=0, columnspan=3, sticky="w"
        )

    def _browse_source(self) -> None:
        filename = filedialog.askopenfilename(
            title="Select MotemaSens binary log",
            filetypes=[("MotemaSens binary logs", "*.bin"), ("All files", "*.*")],
        )
        if not filename:
            return
        source = Path(filename)
        self.source_var.set(str(source))
        self.destination_dir_var.set(str(source.parent))
        self.output_name_var.set(default_destination(source).name)
        self.status_var.set("Ready to convert.")

    def _browse_destination(self) -> None:
        folder = filedialog.askdirectory(title="Select destination folder")
        if folder:
            self.destination_dir_var.set(folder)

    def _use_same_name(self) -> None:
        source_text = self.source_var.get().strip()
        if not source_text:
            messagebox.showinfo("MotemaSens", "Select the BIN file first.")
            return
        self.output_name_var.set(default_destination(Path(source_text)).name)

    def _convert(self) -> None:
        try:
            source = Path(self.source_var.get().strip())
            destination_dir = Path(self.destination_dir_var.get().strip())
            output_name = self.output_name_var.get().strip()
            if not output_name:
                raise ValueError("CSV filename is empty")
            if Path(output_name).suffix.lower() != ".csv":
                output_name += ".csv"
            destination = destination_dir / output_name

            if destination.exists() and not self.overwrite_var.get():
                overwrite = messagebox.askyesno(
                    "Overwrite CSV?",
                    f"{destination.name} already exists.\n\nOverwrite it?",
                )
                if not overwrite:
                    self.status_var.set("Conversion cancelled.")
                    return

            info = inspect_file(source)
            rows = convert_file(source, destination, overwrite=True)
            session_state = "Complete" if info.complete else "Incomplete"
            self.status_var.set(f"{session_state}: {info.status}. Converted {rows} rows to {destination}")
            messagebox.showinfo(
                "MotemaSens",
                f"{session_state} log: {info.status}\n\nConverted {rows} rows.\n\n{destination}",
            )
        except Exception as exc:  # noqa: BLE001 - show a clear user-facing message.
            self.status_var.set(f"Conversion failed: {exc}")
            messagebox.showerror("Conversion failed", str(exc))


def main() -> int:
    app = Bin2CsvApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
