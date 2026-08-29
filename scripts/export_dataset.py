#!/usr/bin/env python3
"""
export_dataset.py — build labeled ML dataset from collected testbed logs.

Reads:
  dataset/logs/<run_dir>/gateway1/eve.json     — Suricata: flows, alerts, HTTP, DNS, SMB, TLS
  dataset/logs/<run_dir>/<client_ip>/audit.log — auditd: rename, exec, connect, file access
  dataset/labels.jsonl                          — attack time windows (from run_attack.sh)

Outputs:
  dataset/dataset.csv   — labeled rows, one per network flow or auditd event

Usage:
  python3 scripts/export_dataset.py
  python3 scripts/export_dataset.py --logs-dir dataset/logs --labels dataset/labels.jsonl --out dataset/dataset.csv

Labels:
  Each row gets the attack_name from labels.jsonl if its timestamp falls in
  a labeled window, otherwise 'benign'. Multi-class — not just ransomware.
"""

import argparse
import csv
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


# ── timestamp helpers ─────────────────────────────────────────────────────────

def parse_suricata_ts(ts):
    """Parse Suricata ISO8601 timestamp: 2026-08-07T10:00:00.123456+0000"""
    ts = re.sub(r'(\+\d{2})(\d{2})$', r'\1:\2', ts)
    for fmt in ('%Y-%m-%dT%H:%M:%S.%f%z', '%Y-%m-%dT%H:%M:%S%z'):
        try:
            return datetime.strptime(ts, fmt)
        except ValueError:
            continue
    return None


def parse_audit_ts(line):
    """Extract datetime from auditd line: msg=audit(1234567890.123:456)"""
    m = re.search(r'msg=audit\((\d+\.\d+):', line)
    if not m:
        return None
    return datetime.fromtimestamp(float(m.group(1)), tz=timezone.utc)


def load_labels(path):
    labels = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                labels.append({
                    'attack': rec['attack'],
                    'start': datetime.fromisoformat(rec['start']),
                    'end': datetime.fromisoformat(rec['end']),
                })
        print(f"Loaded {len(labels)} attack windows from {path}", file=sys.stderr)
    except FileNotFoundError:
        print(f"WARNING: labels file not found: {path} — all rows labeled 'benign'", file=sys.stderr)
    return labels


def get_label(ts, labels):
    if ts is None:
        return 'unknown'
    for lbl in labels:
        if lbl['start'] <= ts <= lbl['end']:
            return lbl['attack']
    return 'benign'


# ── EVE JSON extraction ───────────────────────────────────────────────────────

EVE_INCLUDE_TYPES = {'flow', 'alert', 'http', 'dns', 'smb', 'tls'}

EVE_FIELDS = [
    'timestamp', 'source', 'event_type',
    'src_ip', 'dest_ip', 'src_port', 'dest_port', 'proto', 'app_proto',
    'bytes_toserver', 'bytes_toclient', 'pkts_toserver', 'pkts_toclient', 'flow_duration',
    'http_url', 'http_method', 'http_status',
    'dns_query', 'dns_type', 'dns_rcode',
    'alert_signature', 'alert_category', 'alert_severity',
    'label',
]


def extract_eve_rows(eve_path, labels, source_tag):
    rows = []
    with open(eve_path, errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except json.JSONDecodeError:
                continue
            if evt.get('event_type') not in EVE_INCLUDE_TYPES:
                continue
            ts = parse_suricata_ts(evt.get('timestamp', ''))
            flow = evt.get('flow', {})
            http = evt.get('http', {})
            dns = evt.get('dns', {})
            alert = evt.get('alert', {})
            rows.append({
                'timestamp':       evt.get('timestamp', ''),
                'source':          source_tag,
                'event_type':      evt.get('event_type', ''),
                'src_ip':          evt.get('src_ip', ''),
                'dest_ip':         evt.get('dest_ip', ''),
                'src_port':        evt.get('src_port', ''),
                'dest_port':       evt.get('dest_port', ''),
                'proto':           evt.get('proto', ''),
                'app_proto':       evt.get('app_proto', ''),
                'bytes_toserver':  flow.get('bytes_toserver', ''),
                'bytes_toclient':  flow.get('bytes_toclient', ''),
                'pkts_toserver':   flow.get('pkts_toserver', ''),
                'pkts_toclient':   flow.get('pkts_toclient', ''),
                'flow_duration':   flow.get('duration', ''),
                'http_url':        http.get('url', ''),
                'http_method':     http.get('http_method', ''),
                'http_status':     http.get('status', ''),
                'dns_query':       dns.get('rrname', ''),
                'dns_type':        dns.get('rrtype', ''),
                'dns_rcode':       dns.get('rcode', ''),
                'alert_signature': alert.get('signature', ''),
                'alert_category':  alert.get('category', ''),
                'alert_severity':  alert.get('severity', ''),
                'label':           get_label(ts, labels),
            })
    return rows


# ── auditd extraction ─────────────────────────────────────────────────────────

AUDIT_FIELDS = [
    'timestamp', 'source', 'event_type',
    'syscall', 'success', 'pid', 'uid', 'auid', 'exe', 'key',
    'path_src', 'path_dst',
    'src_ip', 'dest_ip', 'dest_port',
    'label',
]

SYSCALL_NAMES = {
    '2': 'open', '257': 'openat',
    '56': 'clone', '57': 'fork', '59': 'execve',
    '42': 'connect',
    '82': 'rename', '264': 'renameat', '316': 'renameat2',
    '87': 'unlink', '263': 'unlinkat',
}


def _parse_audit_block(lines):
    rec = {}
    paths = []
    for line in lines:
        if 'type=SYSCALL' in line:
            m = re.search(r' syscall=(\d+)', line)
            num = m.group(1) if m else ''
            rec['syscall'] = SYSCALL_NAMES.get(num, num)
            rec['success'] = 'yes' if 'success=yes' in line else 'no'
            for field in ('pid', 'uid', 'auid'):
                m = re.search(rf' {field}=(\S+)', line)
                rec[field] = m.group(1) if m else ''
            m = re.search(r' exe="([^"]+)"', line)
            rec['exe'] = m.group(1) if m else ''
            m = re.search(r' key="([^"]+)"', line)
            rec['key'] = m.group(1) if m else ''
        elif 'type=PATH' in line:
            m = re.search(r' name="([^"]+)"', line)
            if m:
                paths.append(m.group(1))
        elif 'type=SOCKADDR' in line:
            m = re.search(r' laddr=(\S+)', line)
            if m:
                rec['dest_ip'] = m.group(1)
            m = re.search(r' lport=(\d+)', line)
            if m:
                rec['dest_port'] = m.group(1)
    rec['path_src'] = paths[0] if len(paths) > 0 else ''
    rec['path_dst'] = paths[1] if len(paths) > 1 else ''
    return rec


def extract_audit_rows(audit_path, labels, source_tag):
    rows = []
    current_serial = None
    block = []
    ts_line = ''

    def flush(b, tl):
        if not b:
            return
        ts = parse_audit_ts(tl)
        parsed = _parse_audit_block(b)
        if not parsed.get('syscall'):
            return
        rows.append({
            'timestamp':  ts.isoformat() if ts else '',
            'source':     source_tag,
            'event_type': 'auditd_' + (parsed.get('key') or parsed.get('syscall', 'unknown')),
            'syscall':    parsed.get('syscall', ''),
            'success':    parsed.get('success', ''),
            'pid':        parsed.get('pid', ''),
            'uid':        parsed.get('uid', ''),
            'auid':       parsed.get('auid', ''),
            'exe':        parsed.get('exe', ''),
            'key':        parsed.get('key', ''),
            'path_src':   parsed.get('path_src', ''),
            'path_dst':   parsed.get('path_dst', ''),
            'src_ip':     source_tag,
            'dest_ip':    parsed.get('dest_ip', ''),
            'dest_port':  parsed.get('dest_port', ''),
            'label':      get_label(ts, labels),
        })

    with open(audit_path, errors='replace') as f:
        for line in f:
            m = re.search(r'msg=audit\(\d+\.\d+:(\d+)\)', line)
            if not m:
                continue
            serial = m.group(1)
            if serial != current_serial:
                flush(block, ts_line)
                block = [line]
                ts_line = line
                current_serial = serial
            else:
                block.append(line)
        flush(block, ts_line)

    return rows


# ── all columns (union of both sources) ──────────────────────────────────────

ALL_FIELDS = sorted(set(EVE_FIELDS + AUDIT_FIELDS))


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--logs-dir', default='dataset/logs',
                    help='Root directory containing per-run log subdirectories')
    ap.add_argument('--labels', default='dataset/labels.jsonl',
                    help='Attack label file produced by scripts/run_attack.sh')
    ap.add_argument('--out', default='dataset/dataset.csv',
                    help='Output labeled CSV file')
    args = ap.parse_args()

    labels = load_labels(args.labels)

    all_rows = []
    logs_root = Path(args.logs_dir)

    if not logs_root.exists():
        print(f"ERROR: logs directory not found: {logs_root}", file=sys.stderr)
        sys.exit(1)

    for run_dir in sorted(logs_root.iterdir()):
        if not run_dir.is_dir():
            continue
        print(f"Processing run: {run_dir.name}", file=sys.stderr)

        # gateway1: all Suricata EVE JSON files (split per protocol)
        gw_dir = run_dir / 'gateway1'
        if gw_dir.is_dir():
            for eve in sorted(gw_dir.glob('eve-*.json')):
                rows = extract_eve_rows(str(eve), labels, 'gateway1')
                all_rows.extend(rows)
                print(f"  gateway1/{eve.name}: {len(rows)} network events", file=sys.stderr)

        # all host subdirs: auditd logs
        for host_dir in sorted(run_dir.iterdir()):
            if not host_dir.is_dir() or host_dir.name == 'gateway1':
                continue
            audit_log = host_dir / 'audit.log'
            if audit_log.exists():
                rows = extract_audit_rows(str(audit_log), labels, host_dir.name)
                all_rows.extend(rows)
                print(f"  {host_dir.name}/audit.log: {len(rows)} syscall events", file=sys.stderr)

    print(f"\nTotal events: {len(all_rows)}", file=sys.stderr)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=ALL_FIELDS, extrasaction='ignore')
        writer.writeheader()
        for row in all_rows:
            writer.writerow({k: row.get(k, '') for k in ALL_FIELDS})

    print(f"Dataset written → {out}  ({len(all_rows)} rows)", file=sys.stderr)


if __name__ == '__main__':
    main()
