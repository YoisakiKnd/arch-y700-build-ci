#!/usr/bin/env python3
"""Reject a kernel candidate if Kconfig dropped any required profile setting."""
from pathlib import Path
import re
import sys


def read_config(path):
    values = {}
    for line in Path(path).read_text().splitlines():
        match = re.fullmatch(r'(CONFIG_[A-Za-z0-9_]+)=(.*)', line)
        if match:
            values[match[1]] = match[2]
            continue
        match = re.fullmatch(r'# (CONFIG_[A-Za-z0-9_]+) is not set', line)
        if match:
            values[match[1]] = 'n'
    return values


def check(actual_path, required_path):
    actual, required = read_config(actual_path), read_config(required_path)
    if not required:
        raise ValueError('Empty kernel requirements fragment')
    failed = [f'{key}: expected {value}, found {actual.get(key, "absent")}'
              for key, value in required.items() if actual.get(key) != value]
    if 'landlock' not in actual.get('CONFIG_LSM', '').strip('"').split(','):
        failed.append('CONFIG_LSM must retain landlock')
    if failed:
        raise ValueError('\n'.join(failed))
    print(f'PASS: all {len(required)} mobile kernel settings survived olddefconfig; Landlock remains in CONFIG_LSM')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: check-kernel-fragment.py ACTUAL_CONFIG REQUIRED_FRAGMENT')
    check(*sys.argv[1:])
