<div align="center">

# IgniRelay · 烽傳

**Offline-First Field Safety Network**

**English** · [繁體中文](README.zh-Hant.md)

When cell towers fall and the internet goes dark, every phone and every low-cost relay node
becomes a beacon tower — so everyone in the field is **seen, can call for help, and leaves a
last footprint**.

</div>

---

> 📖 **Full story: [`docs/WHITEPAPER.md`](docs/WHITEPAPER.md)** (Traditional Chinese — problem,
> architecture, the E-CARE AI layer, security model, business model, roadmap). The engineering
> source of truth is [`docs/MASTER_EXECUTION_PLAN.md`](docs/MASTER_EXECUTION_PLAN.md).

## What it is

A **field** is any place that gathers people in one area: camps, races, construction sites,
school trips, hiking routes, disaster shelters. IgniRelay gives each field a safety net:

- 📡 **Be seen** — phones emit anonymous presence beacons; organizers see who is still there
  and where each person last appeared.
- 🆘 **Call for help** — one-tap SOS carrying location and safety state (trapped / needs
  medical / safe…), relayed at top priority over every available channel. **No policy can
  ever hide an SOS.**
- 👣 **Leave a last footprint** — every node passed and every phone met keeps a signed trace;
  search areas shrink from square kilometers to "after the last checkpoint".
- 🤖 **Someone picks up after the SOS** — via the partner project **E-CARE**: AI-assisted
  emergency dialog (calming, risk triage, first-aid guidance) when online; bundled offline
  first-aid cards when not.

## Two product forms, one system

| | Software-only | Hardware-enhanced |
|---|---|---|
| Field | camps / races / sites (online) | trails / mines / disaster zones (offline) |
| Transport | phone → HTTPS → cloud | phone → BLE → LoRa nodes → gateway |
| Console | cloud dashboard (any browser) | fully local on-site console (zero internet) |

Same app, same QR join flow, same signed event envelope, same console design language.
Hardware is the field's *offline enhancement pack*, not an entry barrier.

## Architecture in 30 seconds

```
[Phone] --BLE (signed envelope)--> [LoRa Node ×N] --LoRa--> [Gateway] --> local web console
   |  ^                                                        |
   |  └─ phone↔phone mesh / data mule                          └─ (when backhaul exists)
   v                                                                 ↓
[Phone] ---------------HTTPS (the exact same bytes)---------> [Cloud field service] ←→ [E-CARE AI]
```

Core decision: **one envelope everywhere.** Every event is a 141-byte canonical envelope
(Ed25519 author signature + per-field HMAC). BLE, LoRa and HTTPS carry the *same bytes*, and
every hop re-verifies — no relay is trusted, and TLS never substitutes for envelope
verification.

## The E-CARE partnership

> **IgniRelay is the nervous system; E-CARE is the brain.**

[E-CARE](https://github.com/rungyu0721/Ecare) is an AI emergency-response system built by a
partner student team: a locally fine-tuned LLM (Qwen2.5 base, fully on-prem inference),
Psychological-First-Aid dialog strategy, voice emotion recognition, a rule-floor + LLM
two-layer risk engine, local TTS, and a curated first-aid knowledge base. IgniRelay forwards
SOS cases into the E-CARE dashboard and offers its AI dialog after an SOS — with **zero
changes** to E-CARE's code and zero dependency of the SOS path on its availability. All AI
capabilities in whitepaper §4.2 are credited to the E-CARE team.

## Status

| Scope | State |
|---|---|
| Wire contract v3 (envelope + 217-case cross-platform conformance corpus + 13-constant parity) | ✅ frozen |
| App test baseline (469 tests) + 4-layer import linting | ✅ |
| Design language + web console template (zero CDN / zero external resources) | ✅ frozen |
| App core wiring (presence → SOS → hazard → field QR → positioning) | 🔧 in progress |
| Node firmware + gateway (simulators first; hardware purchase gated on green E2E) | 📋 spec frozen |
| On-site console / cloud field service / custom maps / E-CARE integration | 📋 spec frozen |
| Physical hardware (nRF54L15 + SX1262, AS923) | 📋 scheduled, parallel with cloud stage |

Execution order: **A app → B simulators → C on-site console → E cloud + E-CARE → D hardware**
(D runs parallel with E).

## Repos

| Repo | Role |
|---|---|
| this repo (`ignirelay_app/`) | Flutter app + **sole owner of all wire/key contracts** |
| `ignirelay-field-node` | Zephyr firmware (nRF54L15 + SX1262) |
| `ignirelay-gateway` | LoRa aggregation + web console (Python); same codebase serves the cloud profile |
| `ignirelay-lab` | multi-node simulation orchestration + chaos tests |

## Quick start (app)

```bash
cd ignirelay_app
flutter pub get
flutter run        # physical device required — BLE is the core feature
```

Quality gates:

```bash
flutter test --exclude-tags golden
dart run tool/check_layers.dart --strict
flutter analyze
```

## Engineering principles

1. **Offline-first** — every feature must answer "what are you when the network is gone?"
2. **Zero external resources** — no CDN, no external fonts/tiles; the console stands alone in a disaster zone.
3. **Frozen contracts** — wire specs are versioned and frozen; one generated corpus locks all platforms.
4. **Honest positioning** — always "last credible position" with age-based confidence decay, never fake live tracking.
5. **Degradation ladder** — internet → nodes → phone mesh → data mule; every layer has a layer below.

## Security

This project processes untrusted input from unknown nearby devices and contains signing and
key logic. Please **report security issues privately** to the maintainer — do not open a
public issue.

## License & third-party data

- Code license: 〔pending owner confirmation — the fork baseline was labeled AGPL-3.0; a
  formal LICENSE file will be added before public release〕
- Offline geodata under `ignirelay_app/assets/` derives from **OpenStreetMap** (ODbL — keep
  the "© OpenStreetMap contributors" attribution) and other sources under their own terms.

## Acknowledgements

- **The E-CARE team** ([github.com/rungyu0721/Ecare](https://github.com/rungyu0721/Ecare)) —
  partner project powering the intelligent emergency-response layer.
