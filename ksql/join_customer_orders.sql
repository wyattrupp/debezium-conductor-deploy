-- ksqlDB queries to join customers and orders streams
-- Run these in the ksqlDB CLI or via REST API

-- Create stream from customers CDC topic
CREATE STREAM customers_stream (
  customer_id INT KEY,
  first_name VARCHAR,
  last_name VARCHAR,
  email VARCHAR,
  created_at BIGINT,
  updated_at BIGINT
) WITH (
  KAFKA_TOPIC='dw.public.customers',
  VALUE_FORMAT='AVRO',
  KEY_FORMAT='AVRO'
);

-- Create stream from orders CDC topic  
CREATE STREAM orders_stream (
  order_id INT KEY,
  customer_id INT,
  order_date BIGINT,
  total_amount DECIMAL(10,2),
  status VARCHAR,
  updated_at BIGINT
) WITH (
  KAFKA_TOPIC='dw.public.orders',
  VALUE_FORMAT='AVRO',
  KEY_FORMAT='AVRO'
);

-- Create table from customers (for lookup joins)
-- This maintains the latest state of each customer
CREATE TABLE customers_table 
WITH (
  KAFKA_TOPIC='customers_table',
  VALUE_FORMAT='AVRO',
  KEY_FORMAT='AVRO'
) AS
SELECT 
  customer_id,
  LATEST_BY_OFFSET(first_name) as first_name,
  LATEST_BY_OFFSET(last_name) as last_name,
  LATEST_BY_OFFSET(email) as email,
  LATEST_BY_OFFSET(created_at) as created_at,
  LATEST_BY_OFFSET(updated_at) as updated_at
FROM customers_stream
GROUP BY customer_id
EMIT CHANGES;

-- Join orders with customers to create denormalized stream
CREATE STREAM customer_orders_denormalized
WITH (
  KAFKA_TOPIC='customer_orders_denormalized',
  VALUE_FORMAT='AVRO',
  KEY_FORMAT='AVRO',
  PARTITIONS=1,
  REPLICAS=1
) AS
SELECT 
  o.order_id as order_id,
  o.customer_id as customer_id,
  c.first_name as first_name,
  c.last_name as last_name,
  c.email as email,
  o.order_date as order_date,
  o.total_amount as total_amount,
  o.status as status,
  o.updated_at as updated_at
FROM orders_stream o
LEFT JOIN customers_table c ON o.customer_id = c.customer_id
EMIT CHANGES;
