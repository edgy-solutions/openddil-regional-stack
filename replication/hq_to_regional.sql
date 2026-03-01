-- =============================================================================
-- OpenDDIL — Postgres Logical Replication: HQ → Regional Hub
-- =============================================================================
-- Row-filtered replication for tiered hub-and-spoke architecture.
-- HQ publishes a SUBSET of inventory_items to each regional hub based on
-- the region column. Each region subscribes only to its own data.
--
-- PostgreSQL 15+ is required for the WHERE clause on publications.
--
-- This ensures inventory READ state changes made at HQ (by Restate) are
-- pushed down to the Regional Postgres, which ElectricSQL then syncs to Edge.
-- =============================================================================


-- =========================================================================
-- STEP 1: Schema Preparation
-- =========================================================================

-- === Run on HQ Postgres ===
-- Add region column if not present (Phase 1 schema didn't include it):
ALTER TABLE inventory_items ADD COLUMN IF NOT EXISTS region TEXT NOT NULL DEFAULT 'HQ';

-- Enable full replica identity for row-filtered replication:
-- (Required so the WHERE clause can filter on UPDATE/DELETE operations)
ALTER TABLE inventory_items REPLICA IDENTITY FULL;


-- === Run on Regional Postgres ===
-- The table must exist and match the HQ schema exactly:
CREATE TABLE IF NOT EXISTS inventory_items (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT        NOT NULL,
    available_count INTEGER     NOT NULL DEFAULT 0,
    allocated_count INTEGER     NOT NULL DEFAULT 0,
    region          TEXT        NOT NULL DEFAULT 'HQ',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- =========================================================================
-- STEP 2: Create Publication on HQ Postgres (Publisher)
-- =========================================================================
-- Only rows WHERE region = 'EU' are replicated to this regional hub.
-- Each region gets its own publication.

CREATE PUBLICATION pub_inventory_eu
    FOR TABLE inventory_items
    WHERE (region = 'EU');

-- Additional regions:
-- CREATE PUBLICATION pub_inventory_us   FOR TABLE inventory_items WHERE (region = 'US');
-- CREATE PUBLICATION pub_inventory_apac FOR TABLE inventory_items WHERE (region = 'APAC');


-- =========================================================================
-- STEP 3: Create Subscription on Regional Postgres (Subscriber)
-- =========================================================================
-- Run this on the REGIONAL Postgres (openddil_regional database).
-- It subscribes to the row-filtered publication on HQ Postgres.

CREATE SUBSCRIPTION sub_inventory_from_hq
    CONNECTION 'host=host.docker.internal port=5432 dbname=openddil user=openddil password=openddil'
    PUBLICATION pub_inventory_eu
    WITH (
        copy_data = true,              -- Initial bulk copy of matching rows
        create_slot = true,            -- Create replication slot on HQ
        enabled = true,                -- Start replicating immediately
        synchronous_commit = 'off'     -- Async for DDIL resilience
    );

-- For Linux Docker hosts, replace host.docker.internal with 172.17.0.1


-- =========================================================================
-- STEP 4: Verify Replication
-- =========================================================================

-- On HQ: check publication and replication slot
SELECT * FROM pg_publication WHERE pubname = 'pub_inventory_eu';
SELECT slot_name, active FROM pg_replication_slots;

-- On Regional: check subscription status
SELECT * FROM pg_subscription WHERE subname = 'sub_inventory_from_hq';
SELECT * FROM pg_stat_subscription;


-- =========================================================================
-- IMPORTANT NOTES
-- =========================================================================
--
-- 1. DATA FLOW: HQ Postgres → (logical replication) → Regional Postgres.
--    Regional is READ-ONLY for replicated data. All writes go via Redpanda.
--
-- 2. PROCESSING: Restate runs ONLY at HQ. It processes events, updates HQ
--    Postgres, and the changes flow down to Regional via this replication.
--
-- 3. AUTONOMOUS OPERATION: If the link between HQ and Regional breaks:
--    - Regional continues serving stale-but-consistent data to Edge clients
--    - Edge writes still spool to Regional Redpanda
--    - Redpanda Connect buffers events and flushes when uplink returns
--    - Logical replication catches up automatically when reconnected
--
-- 4. TRUNCATE WARNING: Row filters do NOT apply to TRUNCATE.
--    Use DELETE WHERE region = 'EU' instead if you need targeted cleanup.
