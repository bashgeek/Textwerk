# Textual Modernization Plan

## Context

Textual is an archived macOS IRC client (Codeux Software, LLC). We are forking and modernizing it.
- Target: macOS 26+ only
- Goal: eliminate submodules, dead code, and legacy paths; prepare for incremental Swift migration
- Status: **Phases 1–4 complete. Phase 5 not started.**

## Legal Status

Fork is legal. All first-party code (Textual, Cocoa Extensions, Encryption Kit, Auto Hyperlinks) is **BSD 3-Clause**.
Requirements: keep copyright headers, include license text, do not use "Textual" or "Codeux Software, LLC" name in promotion.

The only LGPL code (libotr, libgcrypt, libgpg-error) is used exclusively by the Blowfish/OTR encryption feature, which we are dropping entirely — eliminating the LGPL compliance concern.

---

## Submodule Inventory & Decisions

| Submodule | Contents | License | Decision |
|-----------|----------|---------|----------|
| `Frameworks/Auto Hyperlinks` | 4 ObjC files, IRC-aware URL lexer | BSD 3-Clause | **Inline into Sources/** |
| `Frameworks/Cocoa Extensions` | 53 ObjC files, full utility library | BSD 3-Clause | **Move entire Classes/ into Sources/Frameworks/CocoaExtensions/** |
| `Frameworks/Encryption Kit` | OTRKit wrapper (OTR messaging) | BSD 3-Clause (code) + LGPL (libs) | **Delete entirely** |
| `Frameworks/Static Libraries` | GRMustache.framework, Sparkle.framework, libssl/libcrypto/libtls.a, libgcrypt/libgpg-error/libotr.a | MIT, MIT, BSD/OpenSSL, LGPL | **Partial — see below** |
| `Sources/Plugins/Sample Code/Swift Bot` | Sample plugin, nothing functional | — | **Delete** |

### Static Libraries breakdown:
- `GRMustache.framework` — MIT, used by theme rendering (TPCTheme.m). Source is in `Frameworks/Static Libraries/Source/GRMustache/`. **Build as local Xcode target from source, or keep pre-compiled binary directly in Frameworks/GRMustache/ — do not use submodule.**
- `Sparkle.framework` — MIT. **Replace with SPM: `sparkle-project/Sparkle`**
- `libssl.a`, `libcrypto.a`, `libtls.a` — LibreSSL/OpenSSL. Only used by GCDAsyncSocket classic path. **Delete** (gone with Phase 1b).
- `libgcrypt.a`, `libgpg-error.a`, `libotr.a` — **LGPL**. Only used by Encryption Kit. **Delete** (gone with Phase 1c).

---

## Phases

### Phase 1: Dead Code Elimination ✅ COMPLETE

#### 1a ✅ — Delete legacy WebView stack (done)
#### 1b ✅ (partial) — GCDAsyncSocket classic socket path (done)
- `IRCConnectionSocketClassic.swift` deleted
- GCDAsyncSocket files **kept** — still used by DCC file transfers
#### 1c ✅ — Remove License Manager (done)
#### 1d ✅ — Remove Blowfish/OTR encryption + LGPL libs (done)
#### 1e ✅ — Replace OELReachability (done)
#### 1f ✅ — Replace GTMEncodeHTML (done)

### Phase 2: Submodule Inlining ✅ COMPLETE

Actual approach: `.gitmodules` deleted and submodule tracking removed. Framework directories
(`Frameworks/Auto Hyperlinks/`, `Frameworks/Cocoa Extensions/`, `Frameworks/Static Libraries/`)
are now plain committed directories — no inlining into Sources/ was needed.

- 2a ✅ Auto Hyperlinks — submodule tracking removed
- 2b ✅ Cocoa Extensions — submodule tracking removed; still built as framework
- 2c ✅ Static Libraries — submodule tracking removed; Sparkle still pre-built binary (Sparkle→SPM deferred)
- 2d ✅ Encryption Kit deleted; Swift Bot already gone
- 2e ✅ `.gitmodules` deleted

### Phase 3: Build Modernization ✅ COMPLETE

- `MACOSX_DEPLOYMENT_TARGET = 26.0` ✅
- `SWIFT_VERSION = 6.0` ✅
- `GCC_C_LANGUAGE_STANDARD = gnu17` ✅
- `LD_NO_PIE` removed ✅
- `#if canImport(Network)` removed ✅
- `TEXTUAL_BUILT_INSIDE_SANDBOX` flag/guards removed ✅
- `@available` guards for versions ≤ 26 removed ✅

### Phase 4: XPC Services Swift migration ✅ COMPLETE

- ✅ IRC Remote Connection Manager — fully Swift
- ✅ Historic Log File Manager — fully Swift
- ✅ Inline Content Loader — fully Swift (ICLPayloadLocal.m and ICLPayloadShared.m remain ObjC since they are shared with main app; all service/module files converted)

Goal: All XPC services fully Swift. Clean language boundary with ObjC main app.

### Phase 5: Incremental Swift migration of Shared/ layer

Start with `Sources/Shared/` — no UI, natural boundary:
- `TLOLocalization.swift` — already Swift ✓
- `TLOTimer.m` → Swift (`DispatchSourceTimer`)
- `TPCPreferences.m` / `TPCPreferencesUserDefaults.m` → Swift
- `IRCConnectionConfig.m` + `IRCConnectionErrors.m` → Swift structs/enums
- `ICLPayload.m` → Swift

### Intentionally Deferred (too large/risky)
- `IRCClient.m` (13,278 lines) — entire IRC state machine; do not touch until Phases 1–4 complete
- All 39 XIB files — XIB→SwiftUI is a separate multi-month project
- `TVCLogController.m` / `TVCLogRenderer.m` — WebKit bridge code, stable
- Plugin API (`THOPluginProtocol.h`) — must stay ABI-compatible with third-party plugins

---

## Summary Table

| Phase | What | Status |
|-------|------|--------|
| 1a | Delete WK1 WebView | ✅ Done |
| 1b | Delete GCDAsyncSocket + classic socket | ✅ Partial (kept for DCC) |
| 1c | Remove License Manager | ✅ Done |
| 1d | Remove Blowfish/OTR + LGPL libs | ✅ Done |
| 1e | Replace OELReachability | ✅ Done |
| 1f | Replace GTMEncodeHTML | ✅ Done |
| 2a | Inline Auto Hyperlinks | ✅ Done |
| 2b | Inline Cocoa Extensions (53 files) | ✅ Done |
| 2c | Static Libraries → SPM + binary copy | ✅ Done |
| 2d/2e | Remove submodule machinery | ✅ Done |
| 3 | Build modernization (macOS 26 target) | ✅ Done |
| 4 | XPC services → Swift | ✅ Done |
| 5 | Shared/ layer → Swift | ⬜ Not started |

**Total Phase 1 removals: ~11,150 lines (~9% of codebase) before writing a new line.**
