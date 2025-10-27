# Association Table Debezium Configuration Map

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL Database                       │
│                         (postgres)                           │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Schema: public                                     │    │
│  │  Table: association                                 │    │
│  │                                                     │    │
│  │  Columns (example structure):                       │    │
│  │    - id (PRIMARY KEY)                               │    │
│  │    - entity_a_id                                    │    │
│  │    - entity_b_id                                    │    │
│  │    - relationship_type                              │    │
│  │    - created_at                                     │    │
│  │    - updated_at                                     │    │
│  │    - metadata (JSONB)                               │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ WAL (Write-Ahead Log)
                           │ Logical Replication
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Debezium Source Connector                       │
│              (association_source.json)                       │
│                                                              │
│  Config:                                                     │
│    - Type: PostgreSQL                                        │
│    - Server: association_server                             │
│    - Slot: debezium_association                             │
│    - Table filter: public.association                       │
│    - Plugin: pgoutput                                        │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ CDC Events
                           │ (INSERT/UPDATE/DELETE)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Debezium Pipeline                               │
│              (association_pipeline.json)                     │
│                                                              │
│  Pipeline: association_pipeline                              │
│    ├─ Source: association_source                            │
│    ├─ Transforms: []                                         │
│    └─ Sink: Kafka                                            │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ JSON Events
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kafka Topic                               │
│                  association.events                          │
│                                                              │
│  Event Structure:                                            │
│    {                                                         │
│      "before": {...},      // Previous state (UPDATE/DELETE) │
│      "after": {...},       // Current state (INSERT/UPDATE)  │
│      "op": "c|u|d|r",     // Operation type                  │
│      "ts_ms": 123456789,  // Timestamp                       │
│      "source": {...}      // Metadata                        │
│    }                                                         │
└─────────────────────────────────────────────────────────────┘
```

## Configuration Values to Customize

### Source Configuration (`association_source.json`)

**Required values to update:**
- `database.hostname`: Your PostgreSQL host (default: "postgres")
- `database.port`: PostgreSQL port (default: "5432")
- `database.user`: Database user with replication permissions
- `database.password`: Database password
- `database.dbname`: Database name (default: "postgres")
- `table.include.list`: Full table name including schema (e.g., "public.association")
- `slot.name`: Unique replication slot name (default: "debezium_association")

**Optional values to consider:**
- `column.include.list`: Only capture specific columns (e.g., "public.association.id,public.association.entity_a_id")
- `column.exclude.list`: Exclude specific columns (e.g., "public.association.metadata")
- `snapshot.mode`: "initial" | "never" | "always" | "initial_only"
- `decimal.handling.mode`: "precise" | "double" | "string"
- `time.precision.mode`: "adaptive" | "connect"
- `tombstones.on.delete`: true | false (send null event after delete)
- `heartbeat.interval.ms`: Periodic heartbeat interval (e.g., 30000)
- `schema.include.list`: Limit to specific schemas if needed
- `database.include.list`: For multi-database setups
- `publication.name`: Custom publication name (default: auto-created)
- `signal.data.collection`: Enable signal table for ad-hoc snapshots

### Pipeline Configuration (`association_pipeline.json`)

**Required values to update:**
- `source`: Must match the source name ("association_source")
- `bootstrap.servers`: Kafka broker addresses (e.g., "kafka1:9092,kafka2:9092")
- `topic`: Kafka topic name (default: "association.events")

**Optional transforms to add:**
```json
"transforms": [
  {
    "type": "Filter",
    "predicate": "IsUpdate",
    "config": {
      "condition": "operation == 'UPDATE'"
    }
  },
  {
    "type": "ExtractField",
    "config": {
      "field": "after"
    }
  },
  {
    "type": "RenameField",
    "config": {
      "renames": "entity_a_id:source_id,entity_b_id:target_id"
    }
  },
  {
    "type": "TimestampConverter",
    "config": {
      "field": "created_at",
      "format": "iso8601"
    }
  }
]
```

**Optional sink configurations:**
- `topic.prefix`: Add prefix to all topics
- `key.converter.schemas.enable`: true | false
- `value.converter.schemas.enable`: true | false
- `compression.type`: "none" | "gzip" | "snappy" | "lz4" | "zstd"
- `acks`: "0" | "1" | "all"
- `retries`: Number of retry attempts
- `max.in.flight.requests.per.connection`: Control ordering guarantees

## Example: Filtered Association

If you only want to capture associations of a specific type:

**Source with column projection:**
```json
{
  "column.include.list": "public.association.id,public.association.entity_a_id,public.association.entity_b_id,public.association.relationship_type"
}
```

**Pipeline with filter transform:**
```json
{
  "transforms": [
    {
      "type": "Filter",
      "predicate": "IsPartnerRelationship",
      "config": {
        "condition": "value.after.relationship_type == 'PARTNER'"
      }
    }
  ]
}
```

## Deployment

Run the GitHub Action or use the conductor action directly:
```bash
# Via workflow
gh workflow run debezium-pipelines.yml -f environment=dev

# Direct API call (if needed)
curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @configs/dev/sources/association_source.json \
  http://conductor-url/api/v1/sources
```

## Monitoring

Check replication slot status:
```sql
SELECT * FROM pg_replication_slots WHERE slot_name = 'debezium_association';
```

View publication:
```sql
SELECT * FROM pg_publication_tables WHERE pubname LIKE 'debezium%';
```
