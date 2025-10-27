# Debezium CDC Pipeline Deployment Guide

## Architecture

```
DW Database (customers + orders)
    ↓ Debezium CDC
Kafka Topics (dw.public.customers, dw.public.orders)
    ↓ ksqlDB Stream Processing
Kafka Topic (customer_orders_denormalized)
    ↓ Kafka Connect JDBC Sink
OPS Database (customer_orders_denormalized table)
```

## Prerequisites

- Docker and Docker Compose
- PostgreSQL client tools (psql)
- `act` (for testing GitHub Actions locally)

## Step 1: Start Infrastructure

```powershell
# Start all services
docker-compose up -d

# Wait for services to be ready (30-60 seconds)
docker-compose ps
```

Services running:
- PostgreSQL: localhost:5432
- Kafka: localhost:9092
- Schema Registry: localhost:8081
- ksqlDB Server: localhost:8088
- Kafka Connect: localhost:8083
- Redpanda Console: localhost:8082
- Debezium Conductor: localhost:8080
- Debezium Stage UI: localhost:3000

## Step 2: Setup Databases

```powershell
# Create DW and OPS databases and populate with sample data
.\setup_databases.ps1
```

This creates:
- `dw` database with `customers` and `orders` tables
- `ops` database with `customer_orders_denormalized` table

## Step 3: Deploy Debezium CDC Pipelines

```powershell
# Deploy sources, destinations, and pipelines via GitHub Action
act workflow_dispatch -W .github/workflows/debezium-pipelines.yml --input environment=dev
```

This creates:
- `customers_source` → `customers_destination` → `dw.public.customers` topic
- `orders_source` → `orders_destination` → `dw.public.orders` topic

## Step 4: Setup ksqlDB Stream Processing

```powershell
# Execute ksqlDB queries to create streams and join them
docker exec -it debezium-ksqldb-cli ksql http://ksqldb-server:8088

# Then run the queries from ksql/join_customer_orders.sql
# Or execute them directly:
docker exec -i debezium-ksqldb-server ksql http://localhost:8088 < ksql/join_customer_orders.sql
```

This creates:
- `customers_stream` - stream from customers CDC topic
- `orders_stream` - stream from orders CDC topic
- `customers_table` - table for lookups (latest customer state)
- `customer_orders_denormalized` - joined stream output

## Step 5: Deploy Kafka Connect JDBC Sink

```powershell
# Register the JDBC Sink connector
curl -X POST http://localhost:8083/connectors `
  -H "Content-Type: application/json" `
  -d @kafka-connect/jdbc-sink-customer-orders.json
```

This sinks the `customer_orders_denormalized` topic to the ops database table.

## Step 6: Verify the Pipeline

### Check Kafka Topics
```powershell
# View topics in Redpanda Console
Start-Process "http://localhost:8082"
```

### Check ksqlDB Streams
```powershell
docker exec -it debezium-ksqldb-cli ksql http://ksqldb-server:8088
```
```sql
SHOW STREAMS;
SHOW TABLES;
SELECT * FROM customer_orders_denormalized EMIT CHANGES LIMIT 10;
```

### Check OPS Database
```powershell
$env:PGPASSWORD = "password"
psql -h localhost -p 5432 -U user -d ops -c "SELECT * FROM customer_orders_denormalized;"
```

### Check Connector Status
```powershell
# List connectors
curl http://localhost:8083/connectors

# Check connector status
curl http://localhost:8083/connectors/jdbc-sink-customer-orders/status
```

## Testing the Pipeline

### Insert a new customer in DW
```powershell
$env:PGPASSWORD = "password"
psql -h localhost -p 5432 -U user -d dw
```
```sql
INSERT INTO customers (first_name, last_name, email) 
VALUES ('Alice', 'Wonder', 'alice@example.com');
```

### Insert a new order in DW
```sql
INSERT INTO orders (customer_id, order_date, total_amount, status) 
VALUES (4, CURRENT_TIMESTAMP, 99.99, 'pending');
```

### Verify in OPS database
```powershell
psql -h localhost -p 5432 -U user -d ops -c "SELECT * FROM customer_orders_denormalized WHERE customer_id = 4;"
```

You should see the denormalized row with customer details joined with order details!

## Monitoring

- **Debezium UI**: http://localhost:3000
- **Redpanda Console**: http://localhost:8082
- **Schema Registry**: http://localhost:8081
- **Kafka Connect**: http://localhost:8083
- **ksqlDB**: http://localhost:8088

## Troubleshooting

### Check Debezium Conductor logs
```powershell
docker logs debezium-platform-conductor
```

### Check ksqlDB logs
```powershell
docker logs debezium-ksqldb-server
```

### Check Kafka Connect logs
```powershell
docker logs debezium-kafka-connect
```

### Restart a service
```powershell
docker-compose restart <service-name>
```

### Clean slate (destroy all data)
```powershell
docker-compose down -v
```
