#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import json
from pathlib import Path

def parse_args():
    parser = argparse.ArgumentParser(description="Create editor project files")
    parser.add_argument("--stext", action="store_true", help="Create Sublime Text project")
    parser.add_argument("--vscode", action="store_true", help="Create VS Code project")
    parser.add_argument("--force", action="store_true", help="Overwrite existing files")
    return parser.parse_args()

# Default JSON contents
stext_content = {
    "folders": [
        {"path": "."}
    ]
}

vscode_content = {
    "folders": [
        {"path": "."}
    ],
    "settings": {}
}

def create_stext(stext_file, force):
    if stext_file.exists():
        if force:
            with stext_file.open("w", encoding="utf-8") as f:
                json.dump(stext_content, f, indent=4)
            print(f"Tergantikan {stext_file.name}")
        else:
            print(f"File {stext_file.name} sudah ada!")
    else:
        with stext_file.open("w", encoding="utf-8") as f:
            json.dump(stext_content, f, indent=4)
        print(f"Berhasil membuat {stext_file.name}")


def create_vscode(vscode_file, force):
    if vscode_file.exists():
        if force:
            with vscode_file.open("w", encoding="utf-8") as f:
                json.dump(vscode_content, f, indent=4)
            print(f"Tergantikan {vscode_file.name}")
        else:
            print(f"File {vscode_file.name} sudah ada!")
    else:
        with vscode_file.open("w", encoding="utf-8") as f:
            json.dump(vscode_content, f, indent=4)
        print(f"Berhasil membuat {vscode_file.name}")


def main():
    args = parse_args()
    folder = Path.cwd()
    folder_name = folder.name

    stext_file = Path(f"{folder_name}.sublime-project")
    vscode_file = Path(f"{folder_name}.code-workspace")

    if args.stext or args.vscode:
        if args.stext:
            create_stext(stext_file, args.force)
        if args.vscode:
            create_vscode(vscode_file, args.force)
    else:
        # Interactive mode
        print(f"Pilih jenis project yang ingin dibuat untuk folder '{folder_name}':")
        print(f"[1] Sublime Text ({stext_file.name})")
        print(f"[2] VS Code ({vscode_file.name})")
        print("[3] Keduanya")
        choice = input("Pilihan (1/2/3): ").strip()
        if choice == '1':
            create_stext(stext_file, args.force)
        elif choice == '2':
            create_vscode(vscode_file, args.force)
        elif choice == '3':
            create_stext(stext_file, args.force)
            create_vscode(vscode_file, args.force)
        else:
            print("Pilihan tidak valid.")


if __name__ == "__main__":
    main()
