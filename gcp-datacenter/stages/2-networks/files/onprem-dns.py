#!/usr/bin/env python3
"""Servidor DNS de prueba de la VPC onprem-sim (stages/2-networks/onprem_dns.tf).

Responde con autoridad los registros A de una sola zona, por UDP y por TCP, para probar el
reenvío de Cloud DNS hacia on-premises. Solo usa la biblioteca estándar de Python 3: la VPC
onprem-sim no sale a internet, así que la VM no puede instalar paquetes (por ejemplo dnsmasq).

Uso: onprem-dns.py <config.json>

El archivo de configuración lo genera Terraform:
  {"zone": "corp.example.com.", "bind": "192.168.0.10", "port": 53, "ttl": 300,
   "records": {"dns": "192.168.0.10"}}
"records" va de nombre relativo a la zona ("@" es la raíz de la zona) a una dirección IPv4.

Respuestas:
- nombre de la zona con registro y tipo A (o ANY): NOERROR con la dirección;
- nombre de la zona con registro y otro tipo, o la raíz de la zona sin "@": NOERROR sin
  respuestas;
- otro nombre de la zona sin registro: NXDOMAIN;
- nombre fuera de la zona: REFUSED;
- operación distinta de QUERY: NOTIMP; mensaje mal formado: FORMERR o sin respuesta.
"""

import json
import socket
import socketserver
import struct
import sys
import threading

TYPE_A = 1
TYPE_ANY = 255
CLASS_IN = 1
CLASS_ANY = 255

RCODE_NOERROR = 0
RCODE_FORMERR = 1
RCODE_NXDOMAIN = 3
RCODE_NOTIMP = 4
RCODE_REFUSED = 5

FLAG_QR = 0x8000
FLAG_AA = 0x0400
FLAG_RD = 0x0100


def normalize(name):
    """Nombre en minúsculas y con punto final."""
    name = name.strip().lower()
    return name if name.endswith(".") else name + "."


def load_config(path):
    with open(path, encoding="utf-8") as f:
        raw = json.load(f)
    zone = normalize(raw["zone"])
    records = {}
    for rel, ip in raw.get("records", {}).items():
        fqdn = zone if rel in ("@", "") else normalize(rel + "." + zone)
        records[fqdn] = socket.inet_aton(ip)
    return {
        "zone": zone,
        "bind": raw.get("bind", "0.0.0.0"),
        "port": int(raw.get("port", 53)),
        "ttl": int(raw.get("ttl", 300)),
        "records": records,
    }


def parse_query(msg):
    """Devuelve (id, flags, nombre, tipo, clase, pregunta cruda) o None si no se puede leer."""
    if len(msg) < 12:
        return None
    qid, flags, qdcount = struct.unpack("!HHH", msg[:6])
    if flags & FLAG_QR or qdcount != 1:
        return (qid, flags, None, None, None, b"")
    labels = []
    i = 12
    while True:
        if i >= len(msg):
            return None
        length = msg[i]
        if length == 0:
            i += 1
            break
        if length & 0xC0 or i + 1 + length > len(msg):
            return None
        labels.append(msg[i + 1:i + 1 + length].decode("ascii", "replace"))
        i += 1 + length
    if i + 4 > len(msg):
        return None
    qtype, qclass = struct.unpack("!HH", msg[i:i + 4])
    name = normalize(".".join(labels)) if labels else "."
    return (qid, flags, name, qtype, qclass, msg[12:i + 4])


def build_response(msg, config):
    """Respuesta al mensaje msg, o None si no se puede responder."""
    parsed = parse_query(msg)
    if parsed is None:
        return None
    qid, flags, name, qtype, qclass, question = parsed
    opcode = (flags >> 11) & 0xF
    base_flags = FLAG_QR | (opcode << 11) | (flags & FLAG_RD)

    if name is None:
        return struct.pack("!6H", qid, base_flags | RCODE_FORMERR, 0, 0, 0, 0)
    if opcode != 0:
        return struct.pack("!6H", qid, base_flags | RCODE_NOTIMP, 1, 0, 0, 0) + question

    zone = config["zone"]
    if name != zone and not name.endswith("." + zone):
        return struct.pack("!6H", qid, base_flags | RCODE_REFUSED, 1, 0, 0, 0) + question

    flags_aa = base_flags | FLAG_AA
    address = config["records"].get(name)
    if address is None and name != zone:
        return struct.pack("!6H", qid, flags_aa | RCODE_NXDOMAIN, 1, 0, 0, 0) + question
    if address is None or qtype not in (TYPE_A, TYPE_ANY) or qclass not in (CLASS_IN, CLASS_ANY):
        return struct.pack("!6H", qid, flags_aa | RCODE_NOERROR, 1, 0, 0, 0) + question

    # Respuesta con el nombre comprimido (puntero al byte 12, la pregunta).
    answer = struct.pack("!HHHIH", 0xC00C, TYPE_A, CLASS_IN, config["ttl"], 4) + address
    return struct.pack("!6H", qid, flags_aa | RCODE_NOERROR, 1, 1, 0, 0) + question + answer


def make_handlers(config):
    class UDPHandler(socketserver.BaseRequestHandler):
        def handle(self):
            data, sock = self.request
            response = build_response(data, config)
            if response is not None:
                sock.sendto(response, self.client_address)

    class TCPHandler(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(10)
            while True:
                header = self._read(2)
                if header is None:
                    return
                (length,) = struct.unpack("!H", header)
                data = self._read(length)
                if data is None:
                    return
                response = build_response(data, config)
                if response is None:
                    return
                self.request.sendall(struct.pack("!H", len(response)) + response)

        def _read(self, size):
            chunks = b""
            while len(chunks) < size:
                try:
                    chunk = self.request.recv(size - len(chunks))
                except OSError:
                    return None
                if not chunk:
                    return None
                chunks += chunk
            return chunks

    return UDPHandler, TCPHandler


class UDPServer(socketserver.ThreadingMixIn, socketserver.UDPServer):
    allow_reuse_address = True
    daemon_threads = True


class TCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main(argv):
    if len(argv) != 2:
        print("Uso: onprem-dns.py <config.json>", file=sys.stderr)
        return 2
    config = load_config(argv[1])
    udp_handler, tcp_handler = make_handlers(config)
    address = (config["bind"], config["port"])
    udp = UDPServer(address, udp_handler)
    tcp = TCPServer(address, tcp_handler)
    print("Zona %s en %s:%d (UDP y TCP), %d registros." % (
        config["zone"], config["bind"], config["port"], len(config["records"])), flush=True)
    threading.Thread(target=tcp.serve_forever, daemon=True).start()
    udp.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
