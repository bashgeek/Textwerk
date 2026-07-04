# Textual Modernization Plan

## Context

Textual is an archived macOS IRC client (Codeux Software, LLC). We are forking and modernizing it.
- Target: macOS 26+ only
- Goal: eliminate submodules, dead code, and legacy paths; prepare for incremental Swift migration
- Status: **Not started — planning complete, awaiting execution**

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

### Phase 1: Dead Code Elimination (no risk, do first)

#### 1a — Delete legacy WebView stack
- `TVCLogViewInternalWK1.m` + its private header (~380 lines)
- `webView1:` delegate methods in `TVCLogPolicy.m`
- All `#if` WK1/WK2 conditional guards become unconditional WK2 code
- Rationale: `WebView` was removed in macOS 14 (Sonoma). Target is 26+.

#### 1b — Delete GCDAsyncSocket + classic socket path (~9,500 lines)
Files to delete:
- `Sources/Shared/Library/External Libraries/Sockets/GCDAsyncSocket.m` (8,495 lines)
- `Sources/Shared/Library/External Libraries/Sockets/GCDAsyncSocketExtensions.m`
- `Sources/Shared/Headers/External Libraries/GCDAsyncSocket.h`
- `Sources/Shared/Headers/External Libraries/GCDAsyncSocketExtensions.h`
- `XPC Services/IRC Remote Connection Manager/Classes/IRC/IRCConnectionSocketClassic.swift` (1,017 lines)
- `Sources/Shared/Library/External Libraries/Sockets/GCDAsyncSocket-patch.txt`
- Rationale: XPC service already has `IRCConnectionSocketNWF.swift` using Network.framework. NWF is the live path. NWF has native SOCKS5 support via `NWParameters`.

#### 1c — Remove License Manager
- `Sources/App/Classes/Library/License Manager/Standalone/TLOLicenseManager.m`
- `Sources/App/Classes/Library/License Manager/Standalone/TLOLicenseManagerDownloader.m`
- `Sources/App/Classes/Library/License Manager/Standalone/TLOLicenseManagerLastGen.m`
- `Sources/App/Classes/Dialogs/License Manager/Standalone/` (all 6 dialog files)
- All 41 `#if TEXTUAL_BUILT_WITH_LICENSE_MANAGER` conditional guards → remove dead branches
- Set `TEXTUAL_BUILT_WITH_LICENSE_MANAGER = 0` in xcconfig, then clean up and delete the flag entirely
- Rationale: Community fork of archived project, license server is dead.

#### 1d — Remove Blowfish/OTR encryption + LGPL libs
- `Sources/Plugins/Blowfish Encryption/` (entire directory)
- `Sources/App/Classes/Library/TLOEncryptionManager.m`
- All 44 `#if TEXTUAL_BUILT_WITH_ADVANCED_ENCRYPTION` guards → remove dead branches
- Delete flag `TEXTUAL_BUILT_WITH_ADVANCED_ENCRYPTION` from xcconfig
- Rationale: Blowfish is a broken 1993 cipher. OTR is superseded by Signal Protocol. Removing these also eliminates all LGPL libraries.

#### 1e — Replace OELReachability (~110 lines)
- `Sources/App/Classes/Library/External Libraries/Sockets/OELReachability.m`
- Replace with `NWPathMonitor` from Network.framework (~20 lines of Swift)

#### 1f — Replace GTMEncodeHTML (~60 lines)
- `Sources/App/Classes/Helpers/External Libraries/Google/GTMEncodeHTML.m`
- Replace 2 call sites in `TVCLogScriptEventSink.m` and `TVCLogRenderer.m` with `CFStringTransform` or a Swift string extension

### Phase 2: Submodule Inlining

#### 2a — Inline Auto Hyperlinks
- Copy 4 files into `Sources/App/Classes/Library/AutoHyperlinks/`:
  - `AHHyperlinkScanner.m` + `.h`
  - `AHHyperlinkScannerResult.m` + `.h`
  - `AHHyperlinkScannerResultPrivate.h`
  - `AHLinkLexer.h`
- Update `TLOLinkParser.swift` from `import AutoHyperlinks` to direct `#import`
- Keep BSD copyright headers
- Remove submodule from `.gitmodules`

#### 2b — Inline Cocoa Extensions
- Move `Frameworks/Cocoa Extensions/Classes/` → `Sources/Frameworks/CocoaExtensions/`
- Add all 53 `.m` files to the Xcode project (compile in main app target)
- Update import paths from `<CocoaExtensions/Foo.h>` to `"Foo.h"` or module map
- Remove submodule from `.gitmodules`
- Key classes to be aware of:
  - `XRGlobalModels.m` — NSObjectIsEmpty, XRPerformBlock* macros, swizzling helpers
  - `XRSystemInformation.m` — already has macOS 26/Tahoe support coded in
  - `RCMSecureTransport.m` + `RCMTrustPanel.m` — TLS/cert trust UI
  - `XRPortMapper.m` — UPnP/NAT-PMP for DCC transfers
  - `XRKeychain.m` — keychain access
  - `XRFileSystemMonitor.m` — theme file watching

#### 2c — Handle Static Libraries submodule
- Copy `GRMustache.framework` binary directly into `Frameworks/GRMustache/` (arm64+x86_64 universal, MIT licensed), OR build as local Xcode target from `Source/GRMustache/`
- Replace Sparkle: add SPM package `sparkle-project/Sparkle` (v2.x), remove `Sparkle.framework` binary
- Delete all `.a` static libs (all no longer needed after Phase 1b + 1d)
- Remove Static Libraries submodule from `.gitmodules`

#### 2d — Remove Encryption Kit + Swift Bot submodules
- Remove both from `.gitmodules` (code already deleted in Phase 1d)
- Delete `Sources/Plugins/Sample Code/Swift Bot/` placeholder

#### 2e — Delete `.gitmodules` entirely
After all submodules are handled, remove `.gitmodules` and run `git rm --cached` for each former submodule path.

### Phase 3: Build Modernization

- Raise `MACOSX_DEPLOYMENT_TARGET` from `12.0` → `26.0` in `Configurations/Build/Common/Foundation.xcconfig`
- Remove all `@available(macOS X.Y, *)` guards for versions ≤ 26
- Remove `#if canImport(Network)` guard in `IRCConnectionSocketNWF.swift` (Network.framework is always present)
- Remove `LD_NO_PIE = YES` (x86 artifact; keep `LD_NO_PIE[arch=arm64] = NO`)
- `GCC_C_LANGUAGE_STANDARD = gnu99` → `gnu17`
- `SWIFT_VERSION = 5.0` → `6.0` (enables strict concurrency)
- `TEXTUAL_BUILT_INSIDE_SANDBOX` — always 1 on modern macOS; remove flag, strip `#if` guards
- Clean up xcconfig inheritance (Debug/Standard Release duplicates can be simplified)

### Phase 4: XPC Services Swift migration

The IRC Remote Connection Manager is already Swift. Migrate ObjC glue in the other services:
- `XPC Services/IRC Remote Connection Manager/Classes/Service/RCMProcessDelegate.m` → Swift (66 lines)
- `XPC Services/IRC Remote Connection Manager/Classes/Service/RCMProcessMain.m` → Swift (151 lines)
- `XPC Services/Historic Log File Manager/Classes/*.m` (4 files) → Swift + modern CoreData concurrency
- `XPC Services/Inline Content Loader/Classes/Service/*.m` → Swift

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

| Phase | What | Lines removed | Risk |
|-------|------|--------------|------|
| 1a | Delete WK1 WebView | ~380 | None |
| 1b | Delete GCDAsyncSocket + classic socket | ~9,500 | Low |
| 1c | Remove License Manager | ~600 | None |
| 1d | Remove Blowfish/OTR + LGPL libs | ~500 | None |
| 1e | Replace OELReachability | ~110 | Low |
| 1f | Replace GTMEncodeHTML | ~60 | Low |
| 2a | Inline Auto Hyperlinks | 0 net (move) | Low |
| 2b | Inline Cocoa Extensions (53 files) | 0 net (move) | Medium |
| 2c | Static Libraries → SPM + binary copy | — | Low |
| 2d/2e | Remove submodule machinery | — | Low |
| 3 | Build modernization (macOS 26 target) | — | Low |
| 4 | XPC services → Swift | — | Low |
| 5 | Shared/ layer → Swift | — | Low |

**Total Phase 1 removals: ~11,150 lines (~9% of codebase) before writing a new line.**
