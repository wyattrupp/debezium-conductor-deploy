# PostgreSQL credentials
$PG_USER = "user"
$PG_PASSWORD = "password"
$PG_HOST = "localhost"
$PG_PORT = "5432"

# Set PGPASSWORD environment variable
$env:PGPASSWORD = $PG_PASSWORD

Write-Host "Creating databases..." -ForegroundColor Green

# Create dw database
psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d postgres -c "CREATE DATABASE dw;"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Database 'dw' may already exist or error occurred" -ForegroundColor Yellow
}

# Create ops database
psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d postgres -c "CREATE DATABASE ops;"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Database 'ops' may already exist or error occurred" -ForegroundColor Yellow
}

Write-Host "Setting up dw database..." -ForegroundColor Green
psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d dw -f setup_schemas.sql

Write-Host "Setting up ops database..." -ForegroundColor Green
psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d ops -f setup_ops.sql

Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "- DW database: contains 'customers' and 'orders' tables"
Write-Host "- OPS database: contains 'customer_orders_summary' table (ready for CDC)"

# Clear password from environment
Remove-Item Env:\PGPASSWORD
