#!/usr/bin/env python3
from flask import Flask, jsonify, request
import sqlite3
import os

app = Flask(__name__)
DB_PATH = '/data/cmdb.db'

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS devices
                 (id INTEGER PRIMARY KEY, hostname TEXT UNIQUE, ip TEXT, device_type TEXT, location TEXT)''')
    conn.commit()
    conn.close()

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

@app.route('/api/devices', methods=['GET'])
def list_devices():
    conn = get_db()
    c = conn.cursor()
    c.execute('SELECT * FROM devices')
    devices = [dict(row) for row in c.fetchall()]
    conn.close()
    return jsonify({"results": devices, "total": len(devices)})

@app.route('/api/devices', methods=['POST'])
def create_device():
    data = request.json
    conn = get_db()
    c = conn.cursor()
    try:
        c.execute('INSERT INTO devices (hostname, ip, device_type, location) VALUES (?, ?, ?, ?)',
                  (data['hostname'], data.get('ip', ''), data.get('device_type', 'Unknown'), data.get('location', 'Unknown')))
        conn.commit()
        conn.close()
        return jsonify({"status": "success", "device": data}), 201
    except sqlite3.IntegrityError:
        conn.close()
        return jsonify({"status": "error", "message": "Device already exists"}), 400

@app.route('/api/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=False)
