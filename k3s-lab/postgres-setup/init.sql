-- =============================================================
-- PostgreSQL Demo: Realistic E-Commerce Schema
-- For OpenTelemetry monitoring with Checkmk
-- =============================================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE DATABASE shop;
\c shop;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- =============================================================
-- SCHEMA
-- =============================================================

CREATE TABLE customers (
    id          SERIAL PRIMARY KEY,
    email       VARCHAR(255) UNIQUE NOT NULL,
    first_name  VARCHAR(100),
    last_name   VARCHAR(100),
    country     VARCHAR(50),
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE categories (
    id        SERIAL PRIMARY KEY,
    name      VARCHAR(100) NOT NULL,
    parent_id INT REFERENCES categories(id)
);

CREATE TABLE products (
    id          SERIAL PRIMARY KEY,
    sku         VARCHAR(100) UNIQUE NOT NULL,
    name        VARCHAR(255) NOT NULL,
    category_id INT REFERENCES categories(id),
    price       NUMERIC(10,2),
    stock_qty   INT DEFAULT 0,
    created_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE orders (
    id          SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    status      VARCHAR(50) DEFAULT 'pending',
    total       NUMERIC(10,2),
    created_at  TIMESTAMP DEFAULT NOW(),
    updated_at  TIMESTAMP DEFAULT NOW()
);

CREATE TABLE order_items (
    id         SERIAL PRIMARY KEY,
    order_id   INT REFERENCES orders(id),
    product_id INT REFERENCES products(id),
    qty        INT,
    unit_price NUMERIC(10,2)
);

CREATE TABLE inventory_log (
    id         SERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id),
    change_qty INT,
    reason     VARCHAR(100),
    logged_at  TIMESTAMP DEFAULT NOW()
);

-- =============================================================
-- INDEXES
-- =============================================================
CREATE INDEX idx_orders_customer   ON orders(customer_id);
CREATE INDEX idx_orders_status     ON orders(status);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_customers_country ON customers(country);

-- =============================================================
-- SEED DATA
-- =============================================================

INSERT INTO categories (name, parent_id) VALUES
    ('Electronics', NULL), ('Clothing', NULL), ('Home & Garden', NULL),
    ('Laptops', 1), ('Smartphones', 1), ('T-Shirts', 2),
    ('Jackets', 2), ('Kitchen', 3), ('Garden Tools', 3);

INSERT INTO customers (email, first_name, last_name, country)
SELECT
    'user' || i || '@example.com',
    (ARRAY['Alice','Bob','Carol','Dave','Eve','Frank','Grace','Hank','Iris','Jack'])[1 + (i % 10)],
    (ARRAY['Smith','Jones','Williams','Brown','Davis','Miller','Wilson','Moore','Taylor','Anderson'])[1 + (i % 10)],
    (ARRAY['DE','US','UK','FR','NL','AT','CH','SE','NO','DK'])[1 + (i % 10)]
FROM generate_series(1, 1000) i;

INSERT INTO products (sku, name, category_id, price, stock_qty)
VALUES
  ('SKU-001', 'laptop', 1, 2500.00, 50),
  ('SKU-002', 'phone', 1, 899.00, 50),
  ('SKU-003', 'tablet', 1, 499.00, 50),
  ('SKU-004', 'headphones', 1, 199.00, 50),
  ('SKU-005', 'keyboard', 1, 89.00, 50),
  ('SKU-006', 'monitor', 1, 349.00, 50),
  ('SKU-007', 'mouse', 1, 49.00, 50);

-- Fill remaining products for workload variety
INSERT INTO products (sku, name, category_id, price, stock_qty)
SELECT
    'SKU-' || LPAD((i + 7)::text, 5, '0'),
    'Product ' || (i + 7),
    1 + ((i + 7) % 9),
    (random() * 500 + 10)::numeric(10,2),
    (random() * 200)::int
FROM generate_series(1, 493) i;

INSERT INTO orders (customer_id, status, total, created_at, updated_at)
SELECT
    1 + (random() * 999)::int,
    (ARRAY['pending','processing','shipped','delivered','cancelled'])[1 + (random()*4)::int],
    (random() * 1000 + 20)::numeric(10,2),
    NOW() - (random() * 90)::int * INTERVAL '1 day',
    NOW() - (random() * 10)::int * INTERVAL '1 hour'
FROM generate_series(1, 5000);

INSERT INTO order_items (order_id, product_id, qty, unit_price)
SELECT
    1 + (random() * 4999)::int,
    1 + (random() * 499)::int,
    1 + (random() * 5)::int,
    (random() * 500 + 10)::numeric(10,2)
FROM generate_series(1, 15000);

INSERT INTO inventory_log (product_id, change_qty, reason)
SELECT
    1 + (random() * 499)::int,
    (-10 + (random() * 50)::int),
    (ARRAY['sale','restock','adjustment','return','damage'])[1 + (random()*4)::int]
FROM generate_series(1, 2000);

-- =============================================================
-- MONITORING USER (read-only, for OTel Collector)
-- =============================================================
CREATE USER otel_monitor WITH PASSWORD 'otel_monitor_pw';
GRANT CONNECT ON DATABASE shop     TO otel_monitor;
GRANT CONNECT ON DATABASE postgres TO otel_monitor;
GRANT pg_monitor TO otel_monitor;

\c shop
GRANT USAGE ON SCHEMA public TO otel_monitor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO otel_monitor;
GRANT pg_monitor TO otel_monitor;
GRANT SELECT ON pg_stat_statements TO otel_monitor;
