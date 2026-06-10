# Mode B Field Node Simulator-First Plan

Status: v0.1 execution draft  
Owner: out-of-repo hardware/firmware/gateway sibling work  
App repo role: contract owner for App <-> Node BLE/wire behavior
Alias: Field Node Lab Plan, from simulator to DK to field trial

This document expands `docs/REBUILD_PLAN.md` Phase 3. It answers the practical
question: after Phase 1/2, can the AGENT team build and test the Mode B hardware
system without buying real boards first? The simulator/lab work may start as
soon as the App <-> Node contract is frozen; hardware purchase waits for the
gates below.

Terminology note: this is a Mode B lab/firmware plan. If a whitepaper uses
"Phase 3" for a broader productization phase, this document still refers only
to the Field Node simulator -> DK -> field trial path.

Short answer: yes. Start with simulator-first development. Buy hardware only
after the simulator, wire contracts, and real-target builds are green.

---

## 1. Decision

After Phase 1/2, hand off Phase 3 to AGENTs as a sibling project. Do not put
nRF54L15 firmware, LoRa code, or Gateway backend code inside this Flutter app
repo.

Recommended sibling repos:

```text
ignirelay-field-node/     Zephyr firmware + bsim simulation
ignirelay-gateway/        LoRa receiver + SQLite + local web/export backend
ignirelay-lab/            multi-node simulation orchestration and test reports
```

The Flutter app repo remains responsible for:

```text
App <-> Field Node GATT contract
EventEnvelope v2 / payload contract
wire conformance corpus
phone-side BLE integration
Data Mule behavior
```

---

## 2. Simulator Route

Use the official Zephyr/Nordic simulated nRF54L15 board:

```bash
west build -b nrf54l15bsim/nrf54l15/cpuapp
```

Use the real board target for compile and memory checks, even before hardware is
available:

```bash
west build -b nrf54l15dk/nrf54l15/cpuapp
```

Important distinction:

```text
nrf54l15bsim:
  Good for app logic, Zephyr behavior, simulated BLE/radio activity,
  multi-node protocol tests, queues, ACK/retry, TTL, dedupe, chaos tests.

nrf54l15dk:
  Good for real compile target, memory report, devicetree, Kconfig,
  and later flashing to actual DK hardware.
```

`nrf54l15bsim` is not a full chip/RF/LoRa hardware simulator. It does not prove
real LoRa range, real power use, antenna quality, SPI wiring, or physical RF
performance.

References:

- Nordic/Zephyr nRF54L15 simulated board:
  https://nrfconnectdocs.nordicsemi.com/ncs/latest/zephyr/boards/native/nrf_bsim/doc/nrf54l15bsim.html
- Zephyr BabbleSim:
  https://docs.zephyrproject.org/latest/develop/test/bsim.html
- Zephyr LoRa SX126x driver path:
  https://raw.githubusercontent.com/zephyrproject-rtos/zephyr/main/drivers/lora/Kconfig.sx12xx

---

## 3. Architecture Rule

Keep all disaster-mesh logic independent from the physical LoRa module.

Target shape:

```text
core/
  event model
  priority queue
  event_id dedupe
  HLC
  TTL / hop count
  ACK / retry / backoff
  Bloom or IBLT sync
  store-and-forward

ble/
  phone beacon scanner
  App <-> Node GATT service
  presence/SOS ingestion

transport/
  lora_transport.h
  fake_lora_transport.c
  sx1262_lora_transport.c

gateway/
  gateway uplink packet format
  local event export contract
```

The simulator must use the same core code as real firmware:

```text
Simulated Node A
  core + fake_lora_transport

Real Node A
  core + sx1262_lora_transport
```

If the AGENTs need to rewrite core logic when moving from simulator to hardware,
the abstraction failed.

### 3.1 Resource Budget Gate

`nrf54l15bsim` has simulator-only memory behavior, so every firmware milestone
must also build the real target and review the memory report.

Initial budget target:

```text
nRF54L15 RAM: 256 KB physical
static RAM use: target < 160 KB
reserved for runtime/stack/heap/BLE buffers: >= 64 KB
event queue: fixed size, no unbounded allocation
seen cache: fixed size, no unbounded allocation
Bloom filter: fixed size
IBLT: defer unless Bloom proves insufficient for MVP
event log: not stored only in RAM
```

The exact numbers may change after the first real-target memory report, but the
AGENTs must treat RAM as a hard design constraint from day one.

Hardware purchase requires either meeting the initial RAM target or writing an
explicit exception with the measured memory report and mitigation plan. "Reviewed
and acceptable" is not enough by itself.

### 3.2 LoRa Packet Budget Gate

The firmware must not assume phone-sized BLE payloads can cross LoRa. Define a
small LoRa packet budget before tuning retry and queue behavior.

Initial target:

```text
LoRa packet payload: prefer 64 bytes; 128 bytes is the early upper review line
PRESENCE_EVENT: <= 32 bytes
SOS_EVENT: <= 64 bytes
NODE_HEARTBEAT: <= 32 bytes
ACK packet: <= 12 bytes
event_id: <= 16 bytes
node_id: <= 4 bytes
HLC: 8 bytes
```

If an event cannot fit the budget, the contract must change before hardware
work begins. Do not hide an oversized event behind simulator-only transport.

### 3.3 LoRa Radio Profile Gate

MVP uses raw LoRa point-to-point / store-and-forward packets, not LoRaWAN. Do not
pull in a LoRaWAN network server, join flow, or MAC stack unless the product plan
explicitly changes.

Before hardware purchase, define an initial raw LoRa profile:

```text
region / frequency plan
bandwidth
spreading factor
coding rate
preamble length
TX power target
max packet airtime
retry spacing
channel busy behavior
```

Payload size alone is not a LoRa transport budget. Airtime and retry spacing
must be reviewed before the first field trial.

Lab radio profile and field radio profile may differ. Bench tests should use
low TX power and legal regional settings. Field trials require confirming local
frequency, power, duty, dwell, and listen-before-talk constraints.

### 3.4 Security Minimum

MVP does not need a full trust graph, but every packet format must leave room
for the minimum security and compatibility fields:

```text
field_id
protocol_version
key_id
packet_type
event_id
HLC
payload
CRC/checksum
truncated keyed MAC
```

CRC/checksum detects accidental corruption. A keyed MAC authenticates authorized
field packets. Checksum alone must never be treated as a security mechanism.

MVP may stub keyed MAC during early simulator work, but the packet format and
test vectors must reserve it from day one.

The contract agent must produce test vectors for canonical encoding and
MAC/checksum validation before hardware purchase.

Security tests must include replayed valid packets and expired events. MVP
replay protection can start with event_id dedupe, HLC/timestamp sanity checks,
event expiry, and a field-session epoch.

### 3.5 Node Provisioning

Before hardware bring-up, define how nodes receive identity and field config:

```text
node_id assignment
field_id installation
key_id / test key installation
Gateway node authorization
lost/stolen test-node revocation
lab/dev/field firmware mode distinction
```

MVP provisioning can be simple, such as USB serial config or build-time lab
config. Do not hardcode per-node IDs in source as the normal workflow.

### 3.6 Structured Logs

Every packet decision must emit structured logs that can be read by humans and
AI debugging tools.

Minimum fields:

```text
timestamp_ms
node_id
layer
event_id
packet_seq
src
dst
priority
ttl
action
reason
rssi/snr if available
```

Example:

```text
123456 A LORA_TX seq=31 event=E9F1 dst=B p=P0 ttl=4 reason=sos_priority
123620 B LORA_RX seq=31 event=E9F1 src=A rssi=-82 snr=7 result=new
123700 A ACK_RX seq=31 from=B result=ok
```

---

## 4. What Can Be Tested On A Computer

The computer simulator can test node-to-node transmission as a protocol problem.
It can answer: "If packets are lost, delayed, duplicated, corrupted, or reordered,
does IgniRelay still deliver the right events with the right priority?"

Testable:

```text
Fake Phone -> Simulated Field Node A
Simulated Field Node A -> Fake LoRa Channel
Fake LoRa Channel -> Simulated Field Node B
Simulated Field Node B -> Gateway
Gateway -> SQLite / local event list / CSV/JSON export
```

Also testable:

```text
PRESENCE event creation
SOS event creation
SOS priority over normal events
queue pressure behavior
ACK and retry
bounded backoff
event_id dedupe
HLC merge/order behavior
TTL/hop expiry
store-and-forward after network partition
Bloom/IBLT-style reconciliation
Gateway duplicate suppression
Gateway export format
firmware crash/restart persistence policy
```

For "node-to-node transmission ability", the simulator can test protocol
resilience. It cannot test real RF range.

---

## 5. What Cannot Be Proven Without Hardware

Real hardware is still required for:

```text
LoRa distance / range
RSSI and SNR truth
antenna performance
RF interference in the field
SPI wiring and pin mapping
SX1262 DIO1/BUSY/RESET timing
real GPIO behavior
real RAM/Flash headroom beyond build reports
low-power sleep/wakeup current
battery and solar behavior
legal regional radio settings
Android/iOS real background BLE behavior
phone vendor BLE quirks
```

So the correct claim after simulator success is:

```text
"Core protocol and firmware logic are green."
```

Not:

```text
"The real disaster mesh is field-proven."
```

---

## 6. Bad Channel Model

The simulator must include a configurable `FakeLoRaChannel`. This is where we
test disaster-grade behavior before buying hardware.

Minimum knobs:

```text
packet_loss_percent: 0 / 5 / 20 / 50
delay_ms_min/max: 50 / 5000
duplicate_percent: 0 / 5 / 20
reorder_percent: 0 / 10 / 40
corrupt_percent: 0 / 1 / 5
channel_busy_percent: 0 / 30 / 80
partition_windows: Node A cannot reach Node B for N seconds
asymmetric_link: A can hear B, B cannot hear A
simultaneous_tx_collision: on/off
hidden_node_case: on/off
broadcast_storm_nodes: 0 / 3 / 10
many_nodes_forward_same_event: on/off
gateway_hears_multiple_duplicates: on/off
fake_rssi_dbm: -60 to -125
fake_snr_db: +10 to -20
```

Expected behavior:

```text
SOS/P0 packets bypass lower priority work.
P4/NODE_HEARTBEAT is dropped before P0/P1 events.
Retries are bounded and use backoff.
ACKs are idempotent.
Duplicate event_id never creates duplicate user-visible events.
Expired TTL packets stop circulating.
Corrupt packets are rejected before ACK.
Store-and-forward resumes after partition heals.
Gateway receives one canonical event even if many nodes forward it.
Trace logs explain why a packet was dropped, retried, ACKed, or expired.
```

### 6.1 ACK/Retry Invariants

The bad-channel tests must verify protocol invariants, not only "eventually
delivered" behavior.

Required invariants:

```text
P0/SOS gets the strongest retry policy.
P3/PRESENCE can be delayed or dropped under pressure.
P4/NODE_HEARTBEAT is dropped first when queues are full.
Each packet has a bounded retry count; initial target <= 3.
Retry backoff includes random jitter.
ACKs are idempotent and never create ACK storms.
The same event_id is ACKed/deduped without re-enqueueing user-visible events.
10-node duplicate storm does not create user-visible duplicates.
SOS under channel_busy=80% still preempts P3/P4 traffic.
```

---

## 7. Phone Flow Testing

There are two phone layers.

### 7.1 Fake Phone Actor

This can be fully tested on a computer:

```text
Fake Phone Beacon
  -> Simulated Field Node scan result
  -> PRESENCE_EVENT
  -> priority queue
  -> LoRa packet
  -> other node / Gateway
```

And:

```text
Fake Phone SOS write
  -> Simulated Field Node GATT handler
  -> SOS_EVENT
  -> priority queue
  -> LoRa packet
  -> Gateway
```

This is the correct first E2E path for AGENTs.

### 7.2 Real Phone BLE

This cannot be completely proven on a computer. Real Android/iOS testing is
still required for:

```text
BLE permissions
foreground/background scanning
advertising limits
MTU behavior
vendor-specific BLE bugs
iOS background constraints
Android foreground service behavior
```

The app repo already owns fake/native bridge tests and wire conformance. Phase 3
must add real phone smoke tests only after hardware or a local BLE peripheral
test harness exists.

The App <-> Node GATT contract must explicitly cover:

```text
write with response / write without response policy
notify / indicate usage
MTU fallback behavior
chunk size
chunk sequence number
application-level ACK / receipt
max GATT message size
version negotiation
phone reconnect behavior
duplicate GATT write handling
```

For SOS UX, BLE write success is not enough. The preferred state split is:

```text
Phone writes SOS chunk
Node returns NODE_ACCEPTED event_id
Phone shows "sent to node"
LoRa/Gateway confirmation is tracked as a separate state
```

`NODE_ACCEPTED` means the Field Node validated, deduped, and persisted or
enqueued the event. It does not mean Gateway delivery, and it must not be sent
merely because a BLE write arrived.

Keep receipts separate:

```text
PHONE_TO_NODE_ACCEPTED: Field Node accepted the phone event.
HOP_ACKED: the next LoRa hop received a packet.
GATEWAY_CONFIRMED: Gateway stored the canonical event.
```

### 7.3 Compatibility Claim Boundary

Fake Phone green means:

```text
App/Node wire contract is understandable.
Node can ingest phone-shaped presence/SOS inputs.
Events can enter LoRa routing.
```

Fake Phone green does not mean:

```text
Android background behavior is verified.
iOS background behavior is verified.
BLE permission flows are verified.
MTU negotiation is verified on real devices.
Foreground-service and vendor BLE quirks are solved.
```

---

## 8. AGENT Work Packages

### A. Firmware Agent

Create `ignirelay-field-node` with:

```text
Zephyr app skeleton
nrf54l15bsim target
nrf54l15dk target
core event/queue/dedupe/retry modules
fake_lora_transport
sx1262_lora_transport stub
unit tests for core logic
```

Exit gate:

```text
west build -b nrf54l15bsim/nrf54l15/cpuapp
west build -b nrf54l15dk/nrf54l15/cpuapp
core tests pass
```

### B. Simulation Agent

Build the multi-node simulation runner:

```text
Node A
Node B
Gateway
Fake Phone
Fake LoRa Channel
chaos profile loader
test report output
```

Exit gate:

```text
PRESENCE and SOS pass through Node A -> Node B -> Gateway.
Chaos tests produce deterministic pass/fail reports.
```

### C. Gateway Agent

Create local gateway backend:

```text
LoRa packet receiver interface
fake receiver for simulator
SQLite event store
event list API
CSV export
JSON export
PDF export later
```

Exit gate:

```text
Gateway stores one canonical event per event_id.
Exports include event type, priority, timestamps, route, and last seen node.
```

### D. Contract Agent

Keep firmware aligned with this app repo:

```text
EventEnvelope v2 fields
payload budget
EventType values
priority matrix
GATT UUIDs
chunk framing
wire conformance corpus
```

Exit gate:

```text
Firmware test vectors match Dart/Kotlin/Swift conformance vectors.
No new Mode B contract is invented only inside firmware.
```

### E. QA Agent

Own the scenario matrix:

```text
normal channel
lossy channel
partition and recovery
duplicate storms
queue full
node reboot
gateway reboot
expired TTL
SOS under congestion
fake RSSI/SNR edge values
```

Exit gate:

```text
Every scenario has an expected outcome and a repeatable test.
```

### F. Persistence Agent

Define which state survives node and gateway restart:

```text
queued events awaiting ACK
recent event_id seen cache
retry counters or retry eligibility
node identity/config
gateway event_id duplicate index
gateway export state
```

Exit gate:

```text
Node reboot does not create duplicate user-visible events.
Gateway reboot still suppresses duplicate event_id.
Store-and-forward resumes after restart according to the written policy.
The policy states whether persistent storage is internal flash, external flash,
or a later FRAM/SPI storage option.
```

Persistence record requirements:

```text
Persisted event is valid only with header, length, event_id, payload CRC,
and commit marker.
Node reboot ignores torn or incomplete records.
Event log uses append-only ring storage.
Flash full drops lowest priority records before P0/P1.
Queue full policy is deterministic and logged.
```

---

## 9. Hardware Purchase Gate

Do not buy hardware before these are green:

```text
nrf54l15bsim simulator E2E passes
nrf54l15dk target builds
static RAM < 160 KB or written exception approved
remaining RAM >= 64 KB for stacks/heap/BLE buffers
no unbounded malloc in core path
LoRa packet budget is frozen
raw LoRa radio profile is written
SX1262 pinout/devicetree plan is written
Gateway fake receiver works
PRESENCE and SOS conformance vectors are frozen
bad-channel tests pass at 20% packet loss
ACK/retry invariants pass
10-node duplicate storm test passes
node reboot / gateway reboot persistence tests pass
CRC/checksum and keyed MAC test vectors are ready
replayed valid packet and expired event tests pass
node provisioning plan is written
structured packet-decision log format is implemented
```

Recommended first purchase:

```text
2x nRF54L15 DK
2x SX1262 LoRa SPI module, regional frequency appropriate for deployment
2x matching antennas
USB-C cables
Dupont wires or a simple adapter board
```

Recommended MVP lab kit:

```text
3x nRF54L15 DK
3x SX1262 LoRa SPI module
3x matching antennas
2-3x SPI NOR Flash or SPI FRAM module for persistence tests
1x Raspberry Pi 4/5 for Gateway
optional Nordic Power Profiler Kit II for power work
```

Prefer SX1262 for the first hardware bring-up. Do not start Phase 3 by betting
on LR2021 unless there is a confirmed Zephyr driver, board example, and module
pinout. SX126x is the lower-risk first milestone.

---

## 10. Phase 3 Milestones

### Phase 3A: Simulator Green

```text
Fake Phone -> SimNode A -> FakeLoRa -> SimNode B -> Gateway
```

Acceptance:

```text
PRESENCE delivered
SOS delivered with priority
duplicates suppressed
20% packet loss profile passes
ACK/retry invariants pass
node and gateway reboot tests pass
all decisions traceable in logs
```

### Phase 3B: Real Target Build Green

```text
west build -b nrf54l15dk/nrf54l15/cpuapp
```

Acceptance:

```text
firmware builds for nRF54L15 DK
memory report reviewed
static RAM target reviewed
LoRa packet budget frozen
raw LoRa radio profile written
CRC/checksum and keyed MAC test vectors ready
replayed valid packet and expired event tests pass
node provisioning plan written
devicetree/Kconfig for SX1262 drafted
no simulator-only API leaks into core
```

### Phase 3C: Hardware Bring-Up

Acceptance:

```text
Node boots
logs over UART
BLE scan starts
SX1262 initializes over SPI
Node A sends packet to Node B on bench
```

### Phase 3D: Phone-to-Node

Acceptance:

```text
Android phone -> real Field Node PRESENCE
Android phone -> real Field Node SOS
Node -> LoRa -> Gateway event visible
```

iOS remains a separate gate if no macOS/iPhone lab is available.

### Phase 3E: Field Trial

Acceptance:

```text
outdoor range notes
RSSI/SNR logs
packet delivery report
power notes
failure cases documented
```

---

## 11. AGENT Brief

Copy/paste brief for Phase 3 AGENTs:

```text
Build the Mode B Field Node simulation-first stack as an out-of-repo sibling
project. Do not modify the Flutter app repo except for contract/conformance docs
or fixtures explicitly requested by the contract owner.

Use Zephyr with nrf54l15bsim/nrf54l15/cpuapp for simulator execution and
nrf54l15dk/nrf54l15/cpuapp for real target builds. Implement all mesh behavior
behind transport interfaces so fake LoRa and real SX1262 use the same core
logic.

The first E2E path is:
Fake Phone -> Simulated Field Node A -> Fake LoRa Channel -> Simulated Field
Node B -> Gateway -> SQLite/export.

Prove PRESENCE, SOS priority, ACK/retry, TTL, dedupe, HLC, store-and-forward,
and bad-channel recovery before requesting hardware purchase.
```

---

## 12. Final Rule

Simulator success is enough to justify buying hardware. It is not enough to
claim field readiness.

The correct progression is:

```text
contract green
-> simulator green
-> real target build green
-> buy hardware
-> bench bring-up
-> real phone test
-> field trial
```
