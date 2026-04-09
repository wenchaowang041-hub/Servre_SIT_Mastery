#!/usr/bin/env python3
"""Basic PCIe inventory checker for SIT daily practice."""

from __future__ import annotations

import argparse
import subprocess
import sys
from typing import Dict, List


KEYWORDS: Dict[str, List[str]] = {
    "nvme": [
        "non-volatile memory controller",
        "nvme",
    ],
    "nic": [
        "ethernet controller",
        "network controller",
        "infiniband controller",
    ],
    "npu": [
        "npu",
        "neural",
        "accelerator",
        "processing accelerators",
        "co-processor",
    ],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check PCIe device counts for NVMe, NIC, and NPU."
    )
    parser.add_argument("--expected-nvme", type=int, help="Expected NVMe count.")
    parser.add_argument("--expected-nic", type=int, help="Expected NIC count.")
    parser.add_argument("--expected-npu", type=int, help="Expected NPU count.")
    parser.add_argument(
        "--show-all",
        action="store_true",
        help="Print the full lspci output before the summary.",
    )
    return parser.parse_args()


def run_lspci() -> List[str]:
    try:
        result = subprocess.run(
            ["lspci"],
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        print("[ERROR] 'lspci' not found. Install pciutils first.", file=sys.stderr)
        sys.exit(2)
    except subprocess.CalledProcessError as exc:
        print(f"[ERROR] Failed to run lspci: {exc}", file=sys.stderr)
        sys.exit(exc.returncode or 1)

    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def classify_devices(lines: List[str]) -> Dict[str, List[str]]:
    groups: Dict[str, List[str]] = {name: [] for name in KEYWORDS}

    for line in lines:
        lower_line = line.lower()
        for name, keywords in KEYWORDS.items():
            if any(keyword in lower_line for keyword in keywords):
                groups[name].append(line)
                break

    return groups


def print_group(title: str, items: List[str]) -> None:
    print(f"[INFO] {title} count: {len(items)}")
    if items:
        for item in items:
            print(f"  - {item}")
    else:
        print("  - none")


def check_expected(name: str, actual: int, expected: int | None) -> bool:
    if expected is None:
        print(f"[INFO] {name} expected count not provided; skip threshold check.")
        return True

    if actual == expected:
        print(f"[PASS] {name} count matched expected value {expected}.")
        return True

    print(f"[WARN] {name} count mismatch: expected {expected}, got {actual}.")
    return False


def main() -> int:
    args = parse_args()
    lines = run_lspci()
    groups = classify_devices(lines)

    print("[INFO] PCIe device scan start")
    print(f"[INFO] Total lspci lines: {len(lines)}")

    if args.show_all:
        print("[INFO] Full lspci output:")
        for line in lines:
            print(f"  {line}")

    print_group("NVMe", groups["nvme"])
    print_group("NIC", groups["nic"])
    print_group("NPU", groups["npu"])

    results = [
        check_expected("NVMe", len(groups["nvme"]), args.expected_nvme),
        check_expected("NIC", len(groups["nic"]), args.expected_nic),
        check_expected("NPU", len(groups["npu"]), args.expected_npu),
    ]

    overall_ok = all(results)
    print(f"[SUMMARY] overall status: {'PASS' if overall_ok else 'WARN'}")
    return 0 if overall_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
