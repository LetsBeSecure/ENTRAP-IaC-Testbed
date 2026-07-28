import base64
from Crypto.Random import get_random_bytes

def generate_key(bits, encode=False):
    content = get_random_bytes(bits)
    if encode:
        return base64.b64encode(content)
    return content

if __name__ == "__main__":
    print(generate_key(32))