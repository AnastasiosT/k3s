#!/usr/bin/env python3
import socket, struct, sys, time, random, os
from datetime import datetime

def generate_netflow_v5_packet(flows):
    version, count = 5, len(flows)
    sys_uptime = int(time.time() * 1000) & 0xFFFFFFFF
    unix_secs = int(time.time())
    # NetFlow v5 header: version, count, sysUptime, unix_secs, unix_nsecs, flow_sequence, engine_type, engine_id, sampling_interval
    header = struct.pack('>HHIIIIBBH',
                        version, count, sys_uptime, unix_secs, 0, 0, 0, 0, 0)
    flow_data = b''
    for flow in flows:
        src_ip = struct.unpack('>I', socket.inet_aton(flow['src_ip']))[0]
        dst_ip = struct.unpack('>I', socket.inet_aton(flow['dst_ip']))[0]
        now_ms = int(time.time() * 1000) & 0xFFFFFFFF
        flow_record = struct.pack('>3I2H4I2H4B2H2BH',
                                 src_ip, dst_ip, 0,                    # srcaddr, dstaddr, nexthop
                                 0, 0,                                 # input, output
                                 flow['packets'], flow['bytes'] & 0xFFFFFFFF, now_ms, now_ms,  # dPackets, dOctets, First, Last
                                 flow['src_port'], flow['dst_port'],   # srcport, dstport
                                 0, flow['flags'], 6, 0,               # pad, tcp_flags, prot, tos
                                 0, 0,                                 # src_as, dst_as
                                 0, 0, 0)                              # src_mask, dst_mask, pad
        flow_data += flow_record
    return header + flow_data

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
collector_host = os.getenv("COLLECTOR", "netflow-collector.otel-collectors.svc.cluster.local")
collector_port = int(os.getenv("NETFLOW_PORT", "2055"))
print(f"NetFlow Generator → {collector_host}:{collector_port}", flush=True)

while True:
    flows = [
        # HTTP traffic (SYN)
        {'src_ip': "10.0.1.10", 'dst_ip': "192.168.1.1", 'src_port': 50000, 'dst_port': 80, 'bytes': 50000, 'packets': 100, 'flags': 0x02},
        # HTTPS traffic (SYN+ACK)
        {'src_ip': "10.0.1.20", 'dst_ip': "192.168.1.5", 'src_port': 50001, 'dst_port': 443, 'bytes': 75000, 'packets': 150, 'flags': 0x12},
        # DNS (SYN+ACK)
        {'src_ip': "10.0.2.10", 'dst_ip': "8.8.8.8", 'src_port': 50002, 'dst_port': 53, 'bytes': 5000, 'packets': 25, 'flags': 0x12},
        # SSH (RST - connection reset)
        {'src_ip': "10.0.1.10", 'dst_ip': "192.168.1.1", 'src_port': 50003, 'dst_port': 22, 'bytes': 10000, 'packets': 50, 'flags': 0x04},
        # MySQL (SYN)
        {'src_ip': "10.0.1.10", 'dst_ip': "192.168.1.1", 'src_port': 50004, 'dst_port': 3306, 'bytes': 100000, 'packets': 200, 'flags': 0x02},
        # PostgreSQL (SYN+ACK)
        {'src_ip': "10.0.1.20", 'dst_ip': "192.168.1.5", 'src_port': 50005, 'dst_port': 5432, 'bytes': 60000, 'packets': 120, 'flags': 0x12},
        # SMTP (SYN)
        {'src_ip': "10.0.2.5", 'dst_ip': "10.0.1.100", 'src_port': 50006, 'dst_port': 25, 'bytes': 35000, 'packets': 70, 'flags': 0x02},
        # LDAP (SYN+ACK)
        {'src_ip': "10.0.1.15", 'dst_ip': "192.168.1.200", 'src_port': 50007, 'dst_port': 389, 'bytes': 45000, 'packets': 90, 'flags': 0x12},
        # NTP (SYN)
        {'src_ip': "10.0.3.1", 'dst_ip': "8.8.8.8", 'src_port': 50008, 'dst_port': 123, 'bytes': 2000, 'packets': 10, 'flags': 0x02},
        # VPN traffic (large flow, SYN+ACK)
        {'src_ip': "10.0.1.30", 'dst_ip': "192.168.100.1", 'src_port': 50009, 'dst_port': 1194, 'bytes': 500000, 'packets': 1000, 'flags': 0x12},
        # Backup traffic (large volume, SYN)
        {'src_ip': "10.0.2.20", 'dst_ip': "192.168.1.50", 'src_port': 50010, 'dst_port': 9102, 'bytes': 250000, 'packets': 500, 'flags': 0x02},
        # Monitoring/Metrics (small steady, SYN+ACK)
        {'src_ip': "10.0.1.5", 'dst_ip': "10.0.1.100", 'src_port': 50011, 'dst_port': 9090, 'bytes': 8000, 'packets': 20, 'flags': 0x12},
        # Attack pattern: SYN+RST (abnormal)
        {'src_ip': "192.168.50.100", 'dst_ip': "192.168.1.1", 'src_port': 50012, 'dst_port': 445, 'bytes': 1000, 'packets': 5, 'flags': 0x06}
    ]
    packet = generate_netflow_v5_packet(flows)
    sock.sendto(packet, (collector_host, collector_port))
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Sent 5 flows", flush=True)
    time.sleep(60)
