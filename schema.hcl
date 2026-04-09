schema "public" {}

table "local_tactical_alerts" {
  schema = schema.public
  column "id" {
    null = false
    type = uuid
  }
  column "device_id" {
    null = false
    type = text
  }
  column "event_type" {
    null = false
    type = text
  }
  column "severity" {
    null = false
    type = text
  }
  column "detected_at" {
    null = false
    type = timestamptz
  }
  primary_key {
    columns = [column.id]
  }
}
