#!/usr/bin/env python3
"""
Workload Generator — PostgreSQL OTel Demo
Generates realistic e-commerce traffic across 5 thread types:
  - FastReads   : PK lookups, simple counts         (<5ms)
  - MediumReads : joins, aggregations per customer  (5-50ms)
  - SlowQueries : full 90-day reports, ILIKE scans  (50-500ms+)
  - WriteLoad   : new orders, stock updates, status transitions
  - LockSim     : occasional row-level lock contention
"""

import psycopg2
import time
import random
import threading
import logging
import os

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(threadName)s] %(levelname)s: %(message)s"
)
log = logging.getLogger(__name__)

DB_CONFIG = {
    "host":     os.getenv("PG_HOST", "postgres"),
    "port":     int(os.getenv("PG_PORT", 5432)),
    "dbname":   os.getenv("PG_DB", "shop"),
    "user":     os.getenv("PG_USER", "postgres"),
    "password": os.getenv("PG_PASSWORD", "postgres"),
}


def get_conn():
    for attempt in range(10):
        try:
            return psycopg2.connect(**DB_CONFIG)
        except psycopg2.OperationalError as e:
            log.warning(f"DB not ready (attempt {attempt+1}): {e}")
            time.sleep(3)
    raise RuntimeError("Could not connect after 10 attempts")


def fast_reads():
    conn = get_conn()
    conn.autocommit = True
    cur = conn.cursor()
    log.info("Started")
    while True:
        try:
            cur.execute("SELECT id, email, country FROM customers WHERE id = %s",
                        (random.randint(1, 1000),))
            cur.fetchone()
            cur.execute("SELECT id, name, price, stock_qty FROM products WHERE id = %s",
                        (random.randint(1, 500),))
            cur.fetchone()
            cur.execute("SELECT COUNT(*) FROM orders WHERE status = 'pending'")
            cur.fetchone()
        except Exception as e:
            log.error(f"Error: {e}")
            conn = get_conn(); conn.autocommit = True; cur = conn.cursor()
        time.sleep(0.1)


def medium_reads():
    conn = get_conn()
    conn.autocommit = True
    cur = conn.cursor()
    log.info("Started")
    while True:
        try:
            cur.execute("""
                SELECT o.id, o.status, o.total, COUNT(oi.id) AS items
                FROM orders o
                LEFT JOIN order_items oi ON o.id = oi.order_id
                WHERE o.customer_id = %s
                GROUP BY o.id ORDER BY o.created_at DESC LIMIT 10
            """, (random.randint(1, 1000),))
            cur.fetchall()

            cur.execute("""
                SELECT c.name, SUM(oi.qty * oi.unit_price) AS revenue
                FROM order_items oi
                JOIN products p    ON oi.product_id = p.id
                JOIN categories c  ON p.category_id = c.id
                JOIN orders o      ON oi.order_id = o.id
                WHERE o.created_at > NOW() - INTERVAL '30 days'
                  AND o.status != 'cancelled'
                GROUP BY c.name ORDER BY revenue DESC
            """)
            cur.fetchall()

            cur.execute("""
                SELECT sku, name, stock_qty FROM products
                WHERE stock_qty < 10 ORDER BY stock_qty LIMIT 20
            """)
            cur.fetchall()
        except Exception as e:
            log.error(f"Error: {e}")
            conn = get_conn(); conn.autocommit = True; cur = conn.cursor()
        time.sleep(0.5)


def slow_queries():
    conn = get_conn()
    conn.autocommit = True
    cur = conn.cursor()
    log.info("Started")
    while True:
        try:
            cur.execute("""
                SELECT DATE_TRUNC('day', o.created_at) AS day,
                       c.country,
                       cat.name AS category,
                       COUNT(DISTINCT o.id)            AS orders,
                       SUM(oi.qty * oi.unit_price)     AS revenue
                FROM orders o
                JOIN customers c    ON o.customer_id = c.id
                JOIN order_items oi ON o.id = oi.order_id
                JOIN products p     ON oi.product_id = p.id
                JOIN categories cat ON p.category_id = cat.id
                WHERE o.created_at > NOW() - INTERVAL '90 days'
                  AND o.status = 'delivered'
                GROUP BY 1, 2, 3
                ORDER BY day DESC, revenue DESC
            """)
            cur.fetchall()

            term = random.choice(['Product 1', 'Product 2', 'SKU', 'Pro'])
            cur.execute("""
                SELECT p.*, c.name AS category_name
                FROM products p
                JOIN categories c ON p.category_id = c.id
                WHERE p.name ILIKE %s
            """, (f'%{term}%',))
            cur.fetchall()
        except Exception as e:
            log.error(f"Error: {e}")
            conn = get_conn(); conn.autocommit = True; cur = conn.cursor()
        time.sleep(3)


def write_workload():
    conn = get_conn()
    cur = conn.cursor()
    log.info("Started")
    counter = 0
    while True:
        try:
            cur.execute("""
                INSERT INTO orders (customer_id, status, total)
                VALUES (%s, 'pending', %s) RETURNING id
            """, (random.randint(1, 1000), round(random.uniform(20, 800), 2)))
            order_id = cur.fetchone()[0]

            for _ in range(random.randint(1, 4)):
                pid = random.randint(1, 500)
                qty = random.randint(1, 3)
                cur.execute("""
                    INSERT INTO order_items (order_id, product_id, qty, unit_price)
                    SELECT %s, %s, %s, price FROM products WHERE id = %s
                """, (order_id, pid, qty, pid))
                cur.execute("""
                    UPDATE products SET stock_qty = GREATEST(0, stock_qty - %s)
                    WHERE id = %s
                """, (qty, pid))
                cur.execute("""
                    INSERT INTO inventory_log (product_id, change_qty, reason)
                    VALUES (%s, %s, 'sale')
                """, (pid, -qty))

            conn.commit()
            counter += 1

            if counter % 15 == 0:
                cur.execute("""
                    UPDATE orders SET status = 'processing', updated_at = NOW()
                    WHERE id IN (
                        SELECT id FROM orders
                        WHERE status = 'pending'
                          AND created_at < NOW() - INTERVAL '5 minutes'
                        LIMIT 5
                    )
                """)
                conn.commit()

        except Exception as e:
            log.error(f"Error: {e}")
            conn.rollback()
            conn = get_conn(); cur = conn.cursor()
        time.sleep(0.3)


def lock_contention():
    """Row-level lock waits — visible in postgresql.database.locks metric"""
    log.info("Started")
    while True:
        time.sleep(random.uniform(20, 45))
        try:
            c1, c2 = get_conn(), get_conn()
            cur1, cur2 = c1.cursor(), c2.cursor()
            p1, p2 = random.randint(1, 500), random.randint(1, 500)
            cur1.execute("BEGIN"); cur2.execute("BEGIN")
            cur1.execute("SELECT * FROM products WHERE id = %s FOR UPDATE", (p1,))
            cur2.execute("SELECT * FROM products WHERE id = %s FOR UPDATE", (p2,))
            time.sleep(2)
            cur1.execute("ROLLBACK"); cur2.execute("ROLLBACK")
            c1.close(); c2.close()
        except Exception:
            pass


if __name__ == "__main__":
    log.info("Waiting for PostgreSQL to be ready...")
    time.sleep(8)
    get_conn().close()
    log.info("Connected! Launching workload threads...")

    threads = [
        threading.Thread(target=fast_reads,      name="FastReads",   daemon=True),
        threading.Thread(target=medium_reads,    name="MediumReads", daemon=True),
        threading.Thread(target=slow_queries,    name="SlowQueries", daemon=True),
        threading.Thread(target=write_workload,  name="WriteLoad",   daemon=True),
        threading.Thread(target=lock_contention, name="LockSim",     daemon=True),
    ]
    for t in threads:
        t.start()

    log.info("All threads running.")
    try:
        while True:
            time.sleep(15)
            log.info("Workload generator alive.")
    except KeyboardInterrupt:
        log.info("Shutdown.")
