# AGENTS.md — OpenDDIL Regional Stack

Guidelines and safety constraints for AI agents working in this repository.

## Repository Scope

This repo contains the **Regional Hub infrastructure** — a Docker Compose stack that provides Edge clients with a closer data proxy and buffers events for forwarding to HQ via **Redpanda Connect** (open-source Benthos).

## ⛔ ABSOLUTE RULES

1. **NEVER add Restate.** Restate runs ONLY at HQ. Split-brain processing would corrupt state.
2. **NEVER use enterprise-licensed features.** No MirrorMaker 2, no Cluster Linking, no proprietary connectors. Redpanda Connect (Apache 2.0) is the bridge.

## What You CAN Do

- **Modify Docker Compose** to adjust resources, update image versions, or add monitoring.
- **Edit `redpanda-connect.yaml`** to tune batching, backoff, or add topics.
- **Add replication SQL** for new tables or regions.
- **Update documentation** (README, llms.txt, .cursorrules, this file).

## What You MUST NOT Do

- ❌ **Never add Restate** — event processing is centralized at HQ only.
- ❌ **Never use MirrorMaker 2 or Cluster Linking** — not open-source compliant.
- ❌ **Never use HQ's ports** (5432, 9092, 8080, 3000) — use the offset ports.
- ❌ **Never write to Regional Postgres** from application code — replicated tables are read-only.
- ❌ **Never add pipeline processors** to `redpanda-connect.yaml` that transform the Protobuf bytes — the bridge is a dumb pipe; transformation happens at HQ via Restate.
- ❌ **Never remove `idempotent_write: true`** from the Connect output — this prevents duplicates.

## Adding a New Region

1. Clone this repo.
2. Update `hq_to_regional.sql`: change `WHERE (region = 'EU')` to the new region code.
3. On HQ Postgres: create a new publication for the region.
4. Optionally adjust ports if running multiple regions on the same host.
5. Set `HQ_REDPANDA_BROKERS` env var to the HQ broker address.
