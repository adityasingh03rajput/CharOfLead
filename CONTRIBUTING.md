# Contributing to CharOfLead

Welcome to the CharOfLead development team. As a commercial multiplayer game with strict deterministic and competitive requirements, maintaining rigorous engineering discipline is our highest priority. 

The following rules are **non-negotiable** for all contributors (both human and AI).

## The Four Gates of Integration
No feature, refactor, or hotfix will be merged into the `main` branch unless it passes the Four Gates automatically in the CI pipeline:
1. **Compile:** The project must build without errors or severe warnings across both Client and Dedicated Server targets.
2. **Unit Tests:** All subsystems (e.g., `ColrTests.gd`) must pass their isolated tests.
3. **Headless Stress Test:** The automated CI framework (`HeadlessStressTest.gd`) must run with configurable network degradation (latency, loss) without failing memory, disconnect, or tick latency thresholds.
4. **Golden Replay Regression:** A canonical "Golden Match" replay must be run through the simulation. The resulting SHA256 output hash must perfectly match the expected hash, definitively proving that determinism has been preserved.

## Core Engineering Rules
- **Decoupled Networking:** Networking code strictly handles inputs and state snapshots. Gameplay rules belong exclusively in the Simulation layer.
- **Deterministic by Design:** All gameplay systems must be fully deterministic given the same random seed and input stream.
- **Incremental Scope:** Never introduce two complex systems at once. (e.g., Do not implement collision *and* weapons in the same PR).
- **Structured Logging:** Use key-value logging for all critical paths (e.g., `[NET] rtt=31 loss=0`). No arbitrary or ad-hoc prints.
- **Strict Versioning:** Any change to a binary packet structure, RPC signature, or replay format requires incrementing the corresponding Version flag in the headers to prevent silent corruption.

By adhering strictly to these guidelines, we ensure CharOfLead scales safely from its v0.1.0 prototype into a massive, stable Steam release.
