-- Create table for CDC to populate
CREATE TABLE IF NOT EXISTS customer_orders_summary (
    customer_id INTEGER PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    total_orders INTEGER,
    total_spent DECIMAL(10, 2),
    last_order_date TIMESTAMP
);
