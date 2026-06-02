---
name: mongodb-complete
description: >-
  MongoDB at staff depth (Server 8.0 / driver v6 / mongosh 2.x, 2026): Atlas + self-host setup,
  document modeling (embed vs reference + bucket/outlier/computed/subset/extended-ref patterns),
  the aggregation framework with real pipelines, the ESR index rule + explain, multi-document
  transactions, change streams, RBAC/network/encryption, Compass, backups, and sharding. Use for
  any MongoDB schema, query, index, or admin task.
---

# MongoDB — Complete (modeling → aggregation → indexing → ops)

**Mandate:** Model for your application's read pattern (documents are pre-joined aggregates, not normalized
tables), index with the **ESR rule**, and operate it like a real database — RBAC on, network locked, backups
restored, slow ops profiled. "Schemaless" is a lie you tell yourself; design the schema deliberately.

## When to use / when NOT to use
- **Use** when reads are document-shaped (fetch one aggregate: entity + its embedded children), schema
  varies per document, write fan-out is high, or you'll shard horizontally. Also great for event/IoT/log
  buckets and catalog/CMS data.
- **NOT** when you need cross-entity joins/ad-hoc analytics, hard multi-row invariants (money/inventory with
  FKs), or strong relational reporting — that's Postgres (→ `supabase-complete`, `neon-postgres-serverless`,
  `systems-platforms-foundation` matrix). Don't reach for Mongo to avoid "writing a schema."

## Mental model
A document is the unit of atomicity and the unit of locality. A single-document update is **always atomic**.
So: **data that is read together and updated together should live together in one document** — until that
document grows unbounded or is contended, at which point you split it. The entire art is choosing the split
line. The 16 MB document cap is a hard wall *and* a design smell detector: if you're approaching it, your
model is wrong (unbounded array → use the bucket/reference pattern).

---

## 1. Setup — Atlas (managed, default) and self-host

### Atlas (use this in production unless you have a reason not to)
```bash
# Atlas CLI — scriptable, reproducible
brew install mongodb-atlas-cli            # or: https://www.mongodb.com/docs/atlas/cli/
atlas auth login
atlas clusters create prod --provider AWS --region US_EAST_1 --tier M10 --mdbVersion 8.0
# Network: do NOT use 0.0.0.0/0. Allowlist your egress / use VPC peering or PrivateLink.
atlas accessLists create --cidr 203.0.113.7/32 --comment "app egress"
atlas dbusers create --username app --role readWrite@appdb --password "$(openssl rand -base64 24)"
```
Atlas gives you replica sets, automated backups + PITR, monitoring, Atlas Search (Lucene), Vector Search, and
online index builds without you operating any of it. Tiers: **M0** free (sandbox), **M10+** for production
(dedicated, backups, no shared-tenant noisy neighbors).

### Self-host (replica set — never run a standalone in prod)
```bash
# A 3-node replica set is the MINIMUM for HA: automatic failover + the durability/txn guarantees.
# /etc/mongod.conf
# replication:
#   replSetName: rs0
# security:
#   authorization: enabled        # auth ON from day one
# net:
#   bindIp: 127.0.0.1,10.0.0.5     # never 0.0.0.0 on a public box
#   tls: { mode: requireTLS, certificateKeyFile: /etc/mongo/mongo.pem }
mongosh --host node1 --eval 'rs.initiate({_id:"rs0",members:[
  {_id:0,host:"node1:27017"},{_id:1,host:"node2:27017"},{_id:2,host:"node3:27017"}]})'
```

### Connect from Node (official `mongodb` driver v6 — the 2026 default)
```ts
// db.ts — ONE MongoClient for the whole process (it manages the connection pool internally)
import { MongoClient, ServerApiVersion } from "mongodb";

const client = new MongoClient(process.env.MONGODB_URI!, {
  serverApi: { version: ServerApiVersion.v1, strict: true, deprecationErrors: true }, // Stable API
  maxPoolSize: 20,          // default is 100 — usually too high; 10–20/instance is plenty
  minPoolSize: 2,
  maxIdleTimeMS: 60_000,
  serverSelectionTimeoutMS: 5_000, // fail fast if the cluster is unreachable
  retryWrites: true,        // default; safe idempotent retry of writes on transient errors
});
export const db = client.db("appdb");
// In serverless, cache the client across invocations (module/global scope) — never connect per request.
```
Pair the driver with **Zod** for validation at the boundary, or use **Mongoose** only if you genuinely want
hooks/middleware/populate. Default to driver + Zod for control and performance.

---

## 2. Document modeling — embed vs reference (the core decision)

| Question | Embed (one document) | Reference (separate collections) |
|---|---|---|
| Read together always? | ✅ embed | ❌ reference |
| Child count bounded & small? | ✅ embed | unbounded → reference |
| Child updated independently / hot? | ❌ (rewrites whole doc) | ✅ reference |
| Child shared by many parents? | ❌ duplication | ✅ reference |
| Need the child without the parent? | ❌ | ✅ reference |
| Risk of hitting 16 MB? | ❌ | ✅ reference |

**Rule:** *embed for "contains" / one-to-few that you read together; reference for one-to-many/many-to-many,
unbounded growth, or independently-hot children.* Default to embedding (it's a join you don't pay for), split
the moment growth is unbounded.

### One-to-few → embed
```js
// user with a few addresses — read & written together, bounded
{ _id, email: "a@b.com",
  addresses: [ { label: "home", line1, city, country }, { label: "work", line1, city, country } ] }
```

### One-to-many (unbounded) → reference (child holds the parent id)
```js
// orders reference the customer; never embed an unbounded order array into the customer
{ _id: ObjectId(), customerId: ObjectId("..."), total: 4200, status: "paid", createdAt: ISODate() }
// index the foreign key on the "many" side so $lookup/queries are IXSCAN:
db.orders.createIndex({ customerId: 1, createdAt: -1 });
```

### Schema design patterns (the ones that matter)
| Pattern | Problem it solves | Shape |
|---|---|---|
| **Bucket** | Unbounded time-series/events would blow the doc or make millions of tiny docs | Group N readings into one doc per hour/device |
| **Computed** | Recomputing sums/averages on every read is expensive | Store the aggregate, update it on write |
| **Subset** | Doc is huge but you usually need only the top N | Keep top-N embedded, rest in another collection |
| **Outlier** | 99% of docs are small, a few are huge (the celebrity) | Flag outliers, overflow their data to a side collection |
| **Extended Reference** | `$lookup` on every read is costly | Duplicate the *few* fields you always show (denormalize), accept controlled staleness |

```js
// BUCKET pattern — IoT/metrics: one doc per device per hour, not one doc per reading
{ deviceId: "sensor-7", hour: ISODate("2026-06-02T22:00:00Z"),
  count: 60, sum_temp: 1320.5,
  readings: [ { t: ISODate("..."), temp: 22.1 }, /* up to ~bucket size */ ] }
// Append with $push + $inc in ONE atomic update; cap with $slice or roll a new bucket when count hits N.

// EXTENDED REFERENCE — store the order with a denormalized snapshot of the customer you always render
{ _id, customerId: ObjectId("..."),
  customer: { name: "Lina", tier: "gold" },   // duplicated on purpose; refresh on customer update
  total: 4200, createdAt: ISODate() }
```

### Enforce a schema (because you do have one)
```js
db.createCollection("orders", { validator: { $jsonSchema: {
  bsonType: "object",
  required: ["customerId", "total", "status", "createdAt"],
  properties: {
    customerId: { bsonType: "objectId" },
    total: { bsonType: "int", minimum: 0 },
    status: { enum: ["pending", "paid", "shipped", "cancelled"] },
    createdAt: { bsonType: "date" },
  },
}}, validationLevel: "strict", validationAction: "error" });
```

---

## 3. Aggregation framework — real pipelines

Order matters: **filter early (`$match` first, on an index), project narrow, then transform.** Only the
*leading* `$match`/`$sort` can use an index; everything after a `$group`/`$unwind` runs in memory.

```js
// Revenue per day for paid orders in a range — index-friendly $match + $sort first
db.orders.aggregate([
  { $match: { status: "paid", createdAt: { $gte: ISODate("2026-01-01") } } }, // uses {status:1, createdAt:-1}
  { $group: { _id: { $dateTrunc: { date: "$createdAt", unit: "day" } },
              revenue: { $sum: "$total" }, orders: { $sum: 1 } } },
  { $sort: { _id: 1 } },
]);
```

```js
// Correct $lookup: filter + project on the JOINED side via the pipeline form, with an index on the FK.
// NEVER $lookup → $unwind → $group to re-collapse (that's an N×M blowup).
db.posts.aggregate([
  { $match: { authorId: ObjectId("...") } },
  { $lookup: {
      from: "comments",
      let: { pid: "$_id" },
      pipeline: [
        { $match: { $expr: { $eq: ["$postId", "$$pid"] } } }, // comments.postId must be indexed
        { $sort: { createdAt: -1 } },
        { $limit: 5 },
        { $project: { author: 1, body: 1, createdAt: 1 } },
      ],
      as: "recentComments",
  }},
]);
```

```js
// $facet — multiple aggregations over the same input in one round trip (dashboards / search + count)
db.products.aggregate([
  { $match: { category: "laptops" } },
  { $facet: {
      page:       [ { $sort: { price: 1 } }, { $skip: 0 }, { $limit: 20 } ],
      priceStats: [ { $group: { _id: null, min: { $min: "$price" }, max: { $max: "$price" }, avg: { $avg: "$price" } } } ],
      byBrand:    [ { $group: { _id: "$brand", n: { $sum: 1 } } }, { $sort: { n: -1 } } ],
  }},
]);
```

Use `allowDiskUse: true` **knowingly** for large blocking stages (it spills to disk = slow but won't OOM-fail
the 100 MB in-memory stage limit). Better: make the leading `$match`/`$sort` index-covered so you never spill.

---

## 4. Indexing — the ESR rule + explain

**ESR: Equality → Sort → Range.** In a compound index, put exact-match fields first, then the sort field,
then range filters. Get the order wrong and you get an in-memory sort or a COLLSCAN.

```js
// Query: { tenantId, status:"paid" } sorted by createdAt desc, with total > 100
// ESR index:  Equality (tenantId, status) → Sort (createdAt) → Range (total)
db.orders.createIndex({ tenantId: 1, status: 1, createdAt: -1, total: 1 },
                      { name: "tenant_status_created_total" });
```

| Index type | Use | Note |
|---|---|---|
| Single / Compound | most queries | order by ESR; one good compound > many singles |
| Partial | index a subset | `{ partialFilterExpression: { status: "active" } }` — smaller, less RAM |
| Unique | enforce uniqueness | `{ email: 1 }, { unique: true }` (+ partial for sparse uniqueness) |
| TTL | auto-expire | `{ createdAt: 1 }, { expireAfterSeconds: 2592000 }` for sessions/logs |
| Text / Atlas Search | search | Atlas Search (Lucene) >> legacy `text` index for real search |
| Wildcard | unknown field names | use sparingly; expensive |
| Vector (Atlas) | semantic/RAG | embeddings similarity |

```js
// Prove it: you want IXSCAN, totalDocsExamined ≈ nReturned (1:1), no in-memory SORT stage
db.orders.find({ tenantId, status: "paid" }).sort({ createdAt: -1 }).explain("executionStats");
db.orders.getIndexes();
db.orders.aggregate([{ $indexStats: {} }]); // find & drop UNUSED indexes — they tax every write
```

**Index discipline:** every index slows writes and costs RAM. Index for real query patterns (and the
leading `$match`/`$sort` of aggregations), then drop the unused ones via `$indexStats`. Covered queries
(all fields in the index) skip fetching the document entirely — fastest possible read.

---

## 5. Transactions (multi-document ACID)

Single-document writes are already atomic — **don't reach for a transaction if one document covers it.**
For genuine multi-doc invariants, use a session; the driver retries on transient errors via the
`withTransaction` helper.

```ts
const session = client.startSession();
try {
  await session.withTransaction(async () => {
    const accounts = db.collection("accounts");
    await accounts.updateOne({ _id: from, balance: { $gte: amount } },
      { $inc: { balance: -amount } }, { session });
    const r = await accounts.updateOne({ _id: to }, { $inc: { balance: amount } }, { session });
    if (r.matchedCount !== 1) throw new Error("destination missing"); // aborts the txn
  }, { readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
} finally {
  await session.endSession();
}
```
Requires a replica set (Atlas/your rs0). Keep transactions **short** (default 60s `transactionLifetimeLimitSeconds`),
touch few documents, and design so the *common* path is single-document. `w:"majority"` = durable on a
majority before ack (survives a primary failover).

---

## 6. Change streams (react to data changes)

Tail committed changes (CDC) for cache invalidation, search indexing, webhooks, audit — without polling.
**Always persist and resume from a `resumeToken`** so a reconnect doesn't drop events.

```ts
const stream = db.collection("orders").watch(
  [{ $match: { "fullDocument.status": "paid", operationType: { $in: ["insert", "update"] } } }],
  { fullDocument: "updateLookup", resumeAfter: savedToken /* persist this */ }
);
for await (const change of stream) {
  await onPaidOrder(change.fullDocument);
  await saveResumeToken(change._id); // resume here after a crash; events survive within the oplog window
}
```
Change streams read the oplog, so they only resume within the **oplog retention window** — size the oplog
for your worst expected consumer downtime.

---

## 7. Security — RBAC, network, encryption

- **Auth on, always** (`authorization: enabled`). Least privilege: the app user gets `readWrite` on **its**
  DB only — never `root`/`__system`. Separate users for app vs migrations vs analytics (read-only).
- **Network:** never `0.0.0.0/0`. Atlas: IP allowlist + **VPC peering / PrivateLink**. Self-host: bind to
  private IPs, firewall 27017, `requireTLS`.
- **Encryption:** TLS in transit; encryption at rest (Atlas default / WiredTiger + KMS self-host). For
  field-level secrets, use **Client-Side Field Level Encryption (CSFLE)** / Queryable Encryption so plaintext
  never reaches the server.

```js
// Custom least-privilege role: read everything, write only orders (e.g. an order service)
db.adminCommand({ createRole: "orderWriter",
  privileges: [{ resource: { db: "appdb", collection: "orders" }, actions: ["find","insert","update"] }],
  roles: [{ role: "read", db: "appdb" }] });
db.getSiblingDB("admin").createUser({ user: "order-svc", pwd: passwordPrompt(),
  roles: [{ role: "orderWriter", db: "appdb" }] });
```

---

## 8. Compass & the admin surface (the "full menus")

- **Compass** (GUI): visual query builder, **schema analysis** (field types/frequencies — catch that
  `email` vs `Email` drift), **aggregation pipeline builder** (build visually → export to Node/Python),
  **Explain Plan** tab, **real-time performance** (current ops, hottest collections), index management.
- **mongosh** day-to-day admin:
```js
db.stats(); db.orders.stats();              // sizes, index sizes, doc counts
db.currentOp({ "secs_running": { $gte: 5 } }); db.killOp(opid);   // find/kill a runaway query
db.collection.reIndex();                    // rebuild indexes
db.serverStatus().connections;              // current/available connections — watch saturation
rs.status(); rs.printSecondaryReplicationInfo(); // replication health + lag
db.setProfilingLevel(1, { slowms: 100 });   // slow-op profiler → db.system.profile
```
- **Atlas console:** Metrics (ops/sec, query targeting, connections, replication lag), **Performance
  Advisor** (suggests indexes from real slow queries — use it), Real-Time panel, Online Archive, Triggers,
  Data API, alerts.

---

## 9. Backups, restore, sharding (ops)

**Backups:** Atlas does continuous backups + **PITR** — enable it, know the retention window, and **test a
restore into a scratch cluster**. Self-host: `mongodump`/`mongorestore` (logical, portable) for small data;
filesystem/volume snapshots of a hidden secondary for large data. Store off-provider, encrypted.

```bash
mongodump  --uri="$MONGODB_URI" --gzip --archive="prod_$(date +%F).gz"
mongorestore --uri="$SCRATCH_URI" --gzip --archive="prod_$(date +%F).gz" \
  --nsFrom='prod.*' --nsTo='restore.*'     # verify counts after restore
```

**Sharding** (only when one replica set can't hold the data/throughput — it adds real operational cost):
```js
sh.enableSharding("appdb");
// Choose a shard key that is HIGH-cardinality, evenly distributed, and present in your common queries.
// Hashed → even distribution, kills range queries on the key. Ranged → range queries, risks hot chunks.
sh.shardCollection("appdb.events", { tenantId: 1, _id: 1 });  // compound key avoids a monotonic hotspot
```
A bad shard key is effectively unfixable without a full migration — **do not shard speculatively**. Vertical
scaling + indexes + read-from-secondary solves most "we need to shard" beliefs.

---

## Edge cases & war stories
- **Unbounded array → 16 MB wall.** Embedding every comment/event into one doc works in dev, then a hot doc
  hits 16 MB and *all* writes to it fail. Reference or bucket from the start for unbounded children.
- **COLLSCAN at 2am.** Query `{a, b}` sorted by `c` with only `{a:1}` indexed → in-memory sort + scan. Build
  the ESR compound index; verify with `explain` (want IXSCAN + no SORT stage).
- **`maxPoolSize: 100` × 40 pods** exhausted the Atlas connection limit. Lower it (10–20) and reuse one client.
- **Change stream silently stopped** after a long consumer outage — events aged out of the oplog. Size the
  oplog and persist resume tokens.
- **Monotonic shard key** (`{ createdAt: 1 }` or default `_id`) sent every new write to one shard. Use a
  hashed or compound high-cardinality key.
- **"We don't need transactions"** then a partial multi-doc write corrupted state. Use `withTransaction`
  for true multi-doc invariants, or redesign so one document owns the invariant.

## Performance
- ESR-ordered compound indexes; covered queries where possible; drop unused indexes (`$indexStats`).
- `$match`/`$sort` first and indexed; project narrow before `$group`. Avoid `$lookup`+`$unwind`+`$group`.
- Read from secondaries (`readPreference: "secondaryPreferred"`) for analytics; accept eventual consistency.
- Watch **query targeting** (docs scanned ÷ returned) in Atlas — high ratio = missing/wrong index.

## Security
- Auth on; least-privilege per-service users; never `0.0.0.0/0`; TLS; encryption at rest; CSFLE for PII.

## Scale & reliability
- 3-node replica set minimum (auto-failover, `w:"majority"` durability). Vertical → secondaries → shard last.
  Multi-region for DR. Size the oplog for change-stream/replica resilience.

## Testing
- Use `mongodb-memory-server` or a throwaway container in CI. Assert `explain` returns IXSCAN for hot
  queries (catch a regression where someone drops an index). Validate `$jsonSchema` rejects bad docs.

## Observability
- Profiler (`slowms`) → `system.profile`; Atlas Metrics + Performance Advisor; alert on connections,
  replication lag, query targeting, page faults. Structured logs with correlation ids around DB calls.

## Cost notes
- Atlas billed by tier + storage + backups + (Search/Vector) nodes. Right-size; auto-scale storage; archive
  cold data (Online Archive) instead of paying hot-tier prices for logs you never read.

## Anti-patterns
- Treating "schemaless" as "no schema" → inconsistent fields. Add `$jsonSchema` + Zod.
- Embedding unbounded arrays; storing huge docs near 16 MB.
- One index per field "just in case" (write tax) — index for real queries, drop the rest.
- `$lookup` to fake a relational app (Mongo is not a join engine; if everything is a join, use Postgres).
- Transactions for things one document already makes atomic.
- Public network access / shared admin user / no tested restore.

## Agent checklist
```
- [ ] Embed vs reference decided by the matrix; unbounded children referenced/bucketed
- [ ] $jsonSchema validator + Zod at the app boundary
- [ ] Compound indexes follow ESR; explain shows IXSCAN, no in-memory SORT, ~1:1 docs:returned
- [ ] Unused indexes dropped ($indexStats); TTL on ephemeral collections
- [ ] One MongoClient/process, maxPoolSize 10–20, Stable API, retryWrites
- [ ] Aggregations: $match/$sort first & indexed; $lookup uses pipeline+indexed FK
- [ ] Transactions only for true multi-doc invariants; w:"majority"
- [ ] Change streams persist + resume from resumeToken; oplog sized
- [ ] Auth on, least-privilege users, no 0.0.0.0/0, TLS, encryption at rest, CSFLE for PII
- [ ] PITR/backups enabled AND restore-tested; shard key chosen deliberately (only if needed)
```

## References (2026-current)
- Node.js driver v6: https://www.mongodb.com/docs/drivers/node/current/
- Data modeling & schema patterns ("Building With Patterns"): https://www.mongodb.com/docs/manual/data-modeling/ & https://www.mongodb.com/blog/post/building-with-patterns-a-summary
- ESR index guideline: https://www.mongodb.com/docs/manual/tutorial/equality-sort-range-guideline/
- Aggregation: https://www.mongodb.com/docs/manual/aggregation/
- Transactions: https://www.mongodb.com/docs/manual/core/transactions/
- Change streams: https://www.mongodb.com/docs/manual/changeStreams/
- Atlas CLI: https://www.mongodb.com/docs/atlas/cli/ · Sharding: https://www.mongodb.com/docs/manual/sharding/

## Related
`systems-platforms-foundation`, `supabase-complete`, `neon-postgres-serverless` (this hub) ·
`backend-api-master` (API/auth/data design).
