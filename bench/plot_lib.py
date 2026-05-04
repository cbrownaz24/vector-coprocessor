"""shared plot utils, styling + color map + helpers"""

from __future__ import annotations

import csv
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

THIS_DIR = Path(__file__).resolve().parent
RESULTS_DIR = THIS_DIR / "results"
PLOTS_DIR = THIS_DIR / "plots"


# mpl defaults
def configure_style() -> None:
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 10,
        "axes.titlesize": 11,
        "axes.titleweight": "bold",
        "axes.labelsize": 10,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.alpha": 0.25,
        "grid.linestyle": "-",
        "grid.linewidth": 0.5,
        "axes.axisbelow": True,
        "legend.frameon": False,
        "legend.fontsize": 9,
        "xtick.labelsize": 9,
        "ytick.labelsize": 9,
        "figure.dpi": 130,
        "savefig.dpi": 160,
        "savefig.bbox": "tight",
    })


def load_processors() -> list[dict]:
    return json.loads((THIS_DIR / "processors.json").read_text())["processors"]


def load_benchmarks() -> dict:
    return json.loads((THIS_DIR / "benchmarks.json").read_text())


def load_csv(name: str) -> list[dict]:
    """load csv frmo results/, normalize numeric fields"""
    path = RESULTS_DIR / name
    rows = []
    with path.open() as f:
        for r in csv.DictReader(f):
            for k in ("cycles", "instructions", "size"):
                if k in r:
                    try:
                        r[k] = int(r[k])
                    except ValueError:
                        r[k] = -1
            if "ipc" in r:
                try:
                    r["ipc"] = float(r["ipc"])
                except ValueError:
                    r["ipc"] = 0.0
            if "passed" in r:
                r["passed"] = (r["passed"] == "True")
            if "queue_depth" in r:
                try:
                    r["queue_depth"] = int(r["queue_depth"])
                except ValueError:
                    pass
            rows.append(r)
    return rows


def proc_color(processors: list[dict], name: str) -> str:
    for p in processors:
        if p["name"] == name:
            return p["color"]
    return "#444444"


def proc_label(processors: list[dict], name: str) -> str:
    for p in processors:
        if p["name"] == name:
            return p["label"]
    return name


def save(fig, name: str) -> Path:
    PLOTS_DIR.mkdir(parents=True, exist_ok=True)
    path = PLOTS_DIR / name
    fig.savefig(path)
    plt.close(fig)
    return path
