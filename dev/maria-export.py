#!/usr/bin/env python3
"""
Export MariaDB databases (one file per database/schema).
Cross-platform (Windows/Linux/macOS). Uses mariadb-dump.
"""

import argparse
import os
import platform
import subprocess
import sys
from pathlib import Path

def get_binary(name: str, binary_dir: str | None) -> str:
    """Resolve binary path. Append .exe on Windows if needed."""
    exe = f"{name}.exe" if platform.system() == "Windows" else name
    if binary_dir:
        path = Path(binary_dir) / exe
        if path.is_file():
            return str(path)
        # fallback without .exe
        path = Path(binary_dir) / name
        if path.is_file():
            return str(path)
        raise FileNotFoundError(f"{exe} not found in {binary_dir}")
    return exe  # rely on PATH

def list_databases(mariadb_bin: str, conn_args: list[str]) -> list[str]:
    """Return non-system database names."""
    cmd = [
        mariadb_bin,
        *conn_args,
        "--batch",
        "--skip-column-names",
        "-e",
        "SHOW DATABASES;",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    system = {
        "information_schema",
        "mysql",
        "performance_schema",
        "sys",
        "test",
    }
    return [db.strip() for db in result.stdout.splitlines() if db.strip() and db.strip() not in system]

def dump_database(
    dump_bin: str,
    conn_args: list[str],
    db: str,
    output_dir: Path,
    extra_args: list[str],
) -> None:
    """Dump one database to <output_dir>/<db>.sql"""
    out_file = output_dir / f"{db}.sql"
    cmd = [
        dump_bin,
        *conn_args,
        "--databases",
        db,
        "--single-transaction",
        "--routines",
        "--triggers",
        "--events",
        *extra_args,
    ]
    print(f"Dumping {db} -> {out_file}")
    with open(out_file, "w", encoding="utf-8") as f:
        subprocess.run(cmd, stdout=f, check=True)

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export MariaDB databases (one .sql file per database/schema)."
    )
    parser.add_argument("--host", default="localhost", help="MariaDB host")
    parser.add_argument("--port", type=int, default=3306, help="MariaDB port")
    parser.add_argument("--user", default="root", help="MariaDB user")
    parser.add_argument("--password", default="", help="MariaDB password")
    parser.add_argument("--binary-dir", default=None, help="Directory containing mariadb and mariadb-dump binaries")
    parser.add_argument("--output-dir", default="./mariadb_export", help="Directory to write .sql files")
    parser.add_argument("--databases", nargs="*", default=None, help="Specific databases to export (default: all non-system)")
    parser.add_argument("--extra-args", nargs="*", default=[], help="Extra arguments passed to mariadb-dump")

    args = parser.parse_args()

    try:
        mariadb_bin = get_binary("mariadb", args.binary_dir)
        dump_bin = get_binary("mariadb-dump", args.binary_dir)
    except FileNotFoundError as e:
        print(e, file=sys.stderr)
        sys.exit(1)

    conn_args = [
        f"--host={args.host}",
        f"--port={args.port}",
        f"--user={args.user}",
    ]
    if args.password:
        conn_args.append(f"--password={args.password}")

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.databases:
        dbs = args.databases
    else:
        try:
            dbs = list_databases(mariadb_bin, conn_args)
        except subprocess.CalledProcessError as e:
            print(f"Failed to list databases:\n{e.stderr}", file=sys.stderr)
            sys.exit(1)

    if not dbs:
        print("No databases to export.")
        return

    for db in dbs:
        try:
            dump_database(dump_bin, conn_args, db, output_dir, args.extra_args)
        except subprocess.CalledProcessError as e:
            print(f"Failed to dump {db}: {e}", file=sys.stderr)

    print(f"Done. Files in {output_dir.resolve()}")

if __name__ == "__main__":
    main()