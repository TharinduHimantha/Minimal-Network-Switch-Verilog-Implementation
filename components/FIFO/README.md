# 📦 Streaming Network Packet FIFO Buffer

> A high-performance, byte-streaming FIFO memory subsystem for network switch environments — built for continuous throughput, zero internal fragmentation, and real-time flow control.

---

## 📋 Table of Contents

- [Project Overview](#-project-overview)
- [Key Features](#-key-features)
- [System Architecture](#-system-architecture)
- [Module Interface Definitions](#-module-interface-definitions)

---

## 🔍 Project Overview

This project implements a **Streaming Network Packet FIFO (First-In, First-Out)** buffer designed for a network switch environment. It handles **varying packet sizes dynamically** without wasting valuable memory through internal fragmentation — mirroring industry-standard data streaming protocols like **AXI-Stream**.

Because network components often operate at high speeds, this memory subsystem combines a **Simple Dual-Port RAM** layer with a custom **Pointer & Control Unit**, enabling simultaneous reading and writing on every clock cycle.

---

## ✨ Key Features

| Feature | Description |
|---|---|
| 🔁 **Continuous Byte-Streaming** | Data is packed sequentially without rigid slot boundaries |
| 📌 **Packet Boundary Tracking** | Embedded sideband metadata tracks SOP and EOP flags directly inside memory |
| ⚡ **Automated Pointer Roll-Over** | Uses hardware-native binary arithmetic rollover for clean, single-cycle circular pointer updates |
| 🚦 **Flow Control Signals** | Evaluates real-time occupancy to assert `ALMOST_FULL` throttle warnings at **75% capacity** |

---

## 🏗 System Architecture

The FIFO architecture is divided into three primary abstraction layers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Layer 1 — Top-Level Wrapper (FIFO)                                         │
│  Handles packing/unpacking of network data and packet control structures     │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 2 — Controller Core (FIFO_Controller)                                │
│  Manages read/write pointers and flag logic                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Layer 3 — Storage Element (SDP_RAM)                                        │
│  Dual-port memory matrix for single-cycle read and write interactions        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Block Diagram

```
   INGRESS (Write Interface)                          EGRESS (Read Interface)
  ══════════════════════════                         ═══════════════════════════

  DATA_IN [7:0] ──────────────┐                  ┌──────────────► DATA_OUT [7:0]
  DIN_SOP ─────────────────┐  │                  │  ┌───────────► DOUT_SOP
  DIN_EOP ──────────────┐  │  │                  │  │  ┌────────► DOUT_EOP
                         ▼  ▼  ▼                  ▼  ▼  ▼
                     ╔══════════════╗          ╔══════════════╗
  WRITE_ENABLE ─────►║              ║          ║              ║
                     ║   Pointer    ║─ write ─►║  Dual-Port   ║
                     ║     &        ║─ read ──►║  RAM Array   ║
  READ_ENABLE ──────►║   Status     ║          ║              ║
                     ║    Logic     ║          ║  (256 × 10b) ║
                     ╚══════════════╝          ╚══════════════╝
                          │    │
                          ▼    ▼
                        FULL  EMPTY
```

> **Memory layout:** 256 locations × 10 bits wide — 8 data bits + 2 sideband bits (SOP + EOP).

---

## 🔌 Module Interface Definitions

### Global Signals

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `CLK` | Input | Wire | Global master clock |
| `RESET` | Input | Wire | Active-high synchronous reset |

### Ingress (Write) Interface

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `WRITE_ENABLE` | Input | Wire | Asserts command to push data into memory |
| `DATA_IN[7:0]` | Input | Wire `[DATA_WIDTH-1:0]` | Incoming network packet payload byte |
| `DIN_SOP` | Input | Wire | **Start of Packet** — high only on the first byte of a packet |
| `DIN_EOP` | Input | Wire | **End of Packet** — high only on the final byte of a packet |

### Egress (Read) Interface

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `READ_ENABLE` | Input | Wire | Asserts command to pop data from memory |
| `DATA_OUT[7:0]` | Output | Wire `[DATA_WIDTH-1:0]` | Outgoing network packet payload byte |
| `DOUT_SOP` | Output | Wire | **Start of Packet** — re-aligned metadata indicator |
| `DOUT_EOP` | Output | Wire | **End of Packet** — re-aligned metadata indicator |

### Status Monitors

| Port | Direction | Type | Description |
|------|-----------|------|-------------|
| `FULL` | Output | Wire | Memory completely packed — stalls write requests |
| `EMPTY` | Output | Wire | Memory entirely depleted — stalls read requests |
| `ALMOST_FULL` | Output | Wire | Watermark hit (**≥ 75% full**) — backpressure warning flag |

---

<div align="center">
  <sub>Built for high-throughput network switching environments.</sub>
</div>
