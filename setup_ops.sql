-- Create table for CDC to populate (legacy aggregate table)
CREATE TABLE IF NOT EXISTS customer_orders_summary (
    customer_id INTEGER PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    total_orders INTEGER,
    total_spent DECIMAL(10, 2),
    last_order_date TIMESTAMP
);

-- Create denormalized table for joined customer-order data
CREATE TABLE IF NOT EXISTS customer_orders_denormalized (
    order_id INTEGER PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    order_date TIMESTAMP,
    total_amount DECIMAL(10, 2),
    status VARCHAR(50),
    updated_at TIMESTAMP
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_customer_orders_denorm_customer_id 
    ON customer_orders_denormalized(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_orders_denorm_order_date 
    ON customer_orders_denormalized(order_date);
CREATE INDEX IF NOT EXISTS idx_customer_orders_denorm_status 
    ON customer_orders_denormalized(status);
