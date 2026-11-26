# CONNECT tunnel helper for ssh ProxyCommand (proxy 127.0.0.1:53288)
import socket, sys, threading, select
host, port = sys.argv[1], int(sys.argv[2])
p = socket.create_connection(("127.0.0.1", 53288), timeout=10)
p.sendall(f"CONNECT {host}:{port} HTTP/1.1\r\nHost: {host}:{port}\r\n\r\n".encode())
buf = b""
while b"\r\n\r\n" not in buf:
    d = p.recv(4096)
    if not d: sys.exit(1)
    buf += d
if b" 200 " not in buf.split(b"\r\n")[0]: sys.exit(2)
pairs = [(sys.stdin.buffer, p), (p, sys.stdout.buffer)]
def pump(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d: break
            b.sendall(d)
    except Exception: pass
    try: b.shutdown(socket.SHUT_WR)
    except Exception: pass
t1 = threading.Thread(target=pump, args=pairs[0], daemon=True)
t2 = threading.Thread(target=pump, args=pairs[1], daemon=True)
t1.start(); t2.start()
while t1.is_alive() and t2.is_alive():
    select.select([t1, t2], [], [], 1.0)
sys.exit(0)
