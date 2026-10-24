#!/usr/bin/env python3
"""
Export semua database + semua schema (cross-platform).
Ignore ownership, privileges, security labels.
"""

import os
import sys
import argparse
import subprocess
from datetime import datetime

parser = argparse.ArgumentParser(description="Export PostgreSQL per DB per schema")
parser.add_argument("--host", default="localhost")
parser.add_argument("--port", type=int, default=5432)
parser.add_argument("--user", default="postgres")
parser.add_argument("--password", default="your_password")
parser.add_argument("--output-dir", default="./exports")
parser.add_argument("--binary-dir", default="", help="Path ke folder bin PostgreSQL (opsional)")
args = parser.parse_args()

os.makedirs(args.output_dir, exist_ok=True)
os.environ["PGPASSWORD"] = args.password
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

def bin(name):
    if args.binary_dir:
        return os.path.join(args.binary_dir, name)
    return name

def run(cmd):
    return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)

# Ambil semua database (kecuali template)
cmd_db = [
    bin("psql"), "-h", args.host, "-p", str(args.port), "-U", args.user, "-d", "postgres",
    "-t", "-A", "-c",
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';"
]
try:
    databases = [d for d in run(cmd_db).strip().splitlines() if d]
except FileNotFoundError:
    print("Error: psql/pg_dump tidak ditemukan. Gunakan --binary-dir atau set PATH.")
    sys.exit(1)

for db in databases:
    cmd = [
        bin("psql"), "-h", args.host, "-p", str(args.port), "-U", args.user, "-d", db,
        "-t", "-A", "-c",
        "SELECT nspname FROM pg_namespace WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema';"
    ]
    schemas = [s for s in run(cmd).strip().splitlines() if s]

    for schema in schemas:
        out_file = os.path.join(args.output_dir, f"{db}_{schema}_{timestamp}.sql")
        dump_cmd = [
            bin("pg_dump"),
            "-h", args.host, "-p", str(args.port), "-U", args.user,
            "-d", db,
            "-n", schema,
            "--no-owner",
            "--no-privileges",
            "--no-security-labels",
            "-f", out_file
        ]
        print(f"Exporting {db}.{schema} → {out_file}")
        subprocess.run(dump_cmd, check=True)

print("Done.")