# Popover alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Banner errore in popover sugli avvii falliti + conferma eliminazione in-app al posto di NSAlert.

**Architecture:** `Session.start` espone il motivo di fallimento immediato; UI mostra toast success/error o scheda conferma nella fascia sotto l’header di `RootView`.

**Tech Stack:** SwiftUI MenuBarExtra, DevRunnerCore Session, XCTest esistenti.

## File map

- `Sources/DevRunner/PopoverBanner.swift` — notice kind + confirm chrome
- `Sources/DevRunner/RootView.swift` — slot UI, start failure, RemovalPrompt out
- `Sources/DevRunnerCore/Session.swift` — `start` → `String?`
- `Tests/DevRunnerCoreTests/SessionTests.swift` — assert return value porta busy

## Tasks

- [x] Task 1: `Session.start` returns optional failure message; update busy-port test
- [x] Task 2: Extend `PopoverNotices` / `PopoverBanner` for error; add confirm card API + view
- [x] Task 3: Wire RootView start/restart failures and replace RemovalPrompt with confirm card
- [x] Task 4: Build + run DevRunnerCore tests
