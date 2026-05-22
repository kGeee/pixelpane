# Project Brief: Pixel Pane

## Problem Statement

People constantly encounter text on their screens they cannot understand — foreign-language messages, dense academic passages, menus, technical error messages — and the existing workarounds (switching to a browser translator, opening ChatGPT, copy-pasting between apps) break flow and slow them down. macOS provides no universal, keyboard-triggered way to instantly understand any visible text.

## Proposed Solution

A native macOS app with a global hotkey that opens a drag-select overlay, runs local OCR on the selected region, and shows a compact floating panel with translate, explain, simplify, extract text, and ask actions. The result appears in-place without switching apps.

## Target Users

- Students and self-learners encountering dense or foreign academic material
- Multilingual professionals working across languages in messages and docs
- Everyday users and travelers reading menus, product pages, or signs

## Core Value Proposition

The fastest way to understand foreign or difficult text anywhere on a Mac — without switching apps.

## Key Differentiators

1. Universal: works on any text visible on screen regardless of the source app
2. Privacy-first: local OCR by default, explicit capture only, ephemeral in-memory captures
3. Context-aware output: different result formats for messages, study, menus, and technical content
4. Speed: hotkey → result in under 2 seconds

## Out of Scope (v1)

- Autonomous app control or browser automation
- Continuous screen recording
- Persistent memory across sessions
- Full PDF translation with layout preservation
- Enterprise features

## Success Definition

A user who installs the app stops opening a separate browser tab or chat window to translate or explain on-screen text. Measured by: helpful captures per weekly active user, 7-day retention, and free-to-paid conversion.

## Timeline

| Phase | Scope |
|---|---|
| Launch | Core capture loop, five actions, privacy controls |
| Expansion | Content-aware modes, glossary, PDF import |
| Monetization | Subscriptions, history, Team tier |

## Technical Constraints

- macOS 15.2+ minimum
- Apple Vision for OCR; Apple Foundation Models for on-device text actions and translation when Apple Intelligence is available
- AppKit `NSWindow` for the overlay; ScreenCaptureKit for selected-region capture
- Claude API via backend proxy for cloud explanation/summarization modes
- Direct distribution with Developer ID, Sparkle updates, and Stripe + RevenueCat subscriptions
