"""Prove the new template rows made it into the built HAP."""
import pathlib

HAP = pathlib.Path('entry/build/default/outputs/default/entry-default-unsigned.hap')
blob = HAP.read_bytes()

TOKENS = [
    'peer: %1$s',
    'handshake: %1$s',
    '\u8282\u70b9\uff1a%1$s',      # 节点：
    '\u63e1\u624b\uff1a%1$s',      # 握手：
    '\u7bc0\u9ede\uff1a%1$s',      # 節點：
    'uptime: %1$s',
    '\u8fd0\u884c\u65f6\u95f4',    # 运行时间
]

for token in TOKENS:
    print(f'{blob.count(token.encode("utf-8")):3}  {ascii(token)}')
