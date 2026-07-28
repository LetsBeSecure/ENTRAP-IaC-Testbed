import base64
import hashlib

import generate_keys

from Crypto.Cipher import AES

class AESCipher(object):

    def __init__(self, key):
        self.key = hashlib.sha256(key).digest()

    def encrypt(self, raw):
        if isinstance(raw, str):
            raw = raw.encode('utf-8')
        cipher = AES.new(self.key, AES.MODE_GCM)
        ciphertext, tag = cipher.encrypt_and_digest(raw)
        # format: nonce(16) + tag(16) + ciphertext
        return base64.b64encode(cipher.nonce + tag + ciphertext)

    def decrypt(self, enc, decryption_key=None):
        enc = base64.b64decode(enc)
        nonce = enc[:16]
        tag = enc[16:32]
        ciphertext = enc[32:]
        if decryption_key:
            self.key = hashlib.sha256(decryption_key).digest()
        cipher = AES.new(self.key, AES.MODE_GCM, nonce=nonce)
        return cipher.decrypt_and_verify(ciphertext, tag)

if __name__ == "__main__":
    key = generate_keys.generate_key(32, True)
    cipher_obj = AESCipher(key)
    print("chave: {}".format(key))
    enc = cipher_obj.encrypt("TESTE CRYPTO")
    print(enc)

    back = cipher_obj.decrypt(enc, key)

    print(back)