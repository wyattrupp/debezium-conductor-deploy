-- Create tables in dw database
CREATE TABLE IF NOT EXISTS customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(customer_id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(50) NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO customers (first_name, last_name, email) VALUES
    ('John', 'Doe', 'john.doe@example.com'),
    ('Jane', 'Smith', 'jane.smith@example.com'),
    ('Bob', 'Johnson', 'bob.johnson@example.com')
ON CONFLICT (email) DO NOTHING;

INSERT INTO orders (customer_id, order_date, total_amount, status) VALUES
    (1, CURRENT_TIMESTAMP - INTERVAL '10 days', 150.00, 'completed'),
    (1, CURRENT_TIMESTAMP - INTERVAL '5 days', 200.50, 'completed'),
    (2, CURRENT_TIMESTAMP - INTERVAL '3 days', 75.25, 'pending'),
    (3, CURRENT_TIMESTAMP - INTERVAL '1 day', 300.00, 'completed')
ON CONFLICT DO NOTHING;
