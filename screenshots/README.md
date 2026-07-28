# Regenerating screenshots

`mock_ircd.py` in this directory is a minimal single-client fake IRC server used to
populate Textwerk with a realistic-looking conversation for screenshots, without
needing a real network or real people. This describes how to use it to produce the
screenshots referenced by this website (`images/*.webp`) and by the README on
`master` (`docs/screenshots/*.webp`) — they should be the same shots, kept in sync
across both branches.

Note: the app source on this branch (`Sources/`, `XPC Services/`, etc.) is a stale
snapshot and **not** what you want to build from. Build from `master` (or a worktree
of it) and only use this branch for the mock server, the website assets, and these
instructions.

## 1. Build the app

From a `master` checkout (a separate `git worktree` is easiest, so you don't have to
keep switching branches back and forth):

```sh
git worktree add ../textwerk-build master
cd ../textwerk-build
./build.sh
```

This produces `../textwerk-build/build/Textwerk.app`, built ad-hoc (no code signing
needed).

## 2. Deploy an isolated copy

Screenshots should never run against your real Textwerk install/data. Copy the built
app somewhere scratch, give it a unique bundle ID so it gets its own sandbox
container, and re-sign it with entitlements matching `Sources/App/Configurations/Sandbox/Standard Release.entitlements`
from the build checkout:

```sh
SCRATCH="/tmp/TextwerkShots.app"
rm -rf "$SCRATCH"
cp -R ../textwerk-build/build/Textwerk.app "$SCRATCH"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.textwerk.screenshots" "$SCRATCH/Contents/Info.plist"
codesign --force --deep -s - \
  --entitlements "../textwerk-build/Sources/App/Configurations/Sandbox/Standard Release.entitlements" \
  "$SCRATCH"
```

Re-run this cleanly (delete `~/Library/Containers/app.textwerk.screenshots*` first)
if you want a fresh, un-configured instance rather than reusing one from a previous
session.

## 3. Start the mock server

```sh
python3 screenshots/mock_ircd.py 16667
```

It listens on `127.0.0.1:16667`. Once a client connects and registers, it:

- auto-joins `#textwerk` and `#general` with a populated member list (mixed
  op/voice/unauthenticated users, so the member-list badges have something to show)
- plays out a short, natural-looking conversation in `#textwerk` that deliberately
  includes one **YouTube** link, one **GitHub** link, and one hotlinked **image**, so
  the inline-media preview cards are visible in the shot — that's enough variety to
  show off the feature without cluttering the conversation with every supported
  provider (edit the `seq` list in `simulate_activity()` if you want to change what's
  shown; keep it to a small, plausible number of media links, not a checklist of
  every provider)
- opens a query/DM from a user named `ashby`, for the direct-message screenshot
- simulates someone typing in `#textwerk` a few seconds after connecting (cycles
  through nobody → one person → two people typing, so the indicator's states are all
  exercised if you want a shot of it)

## 4. Connect and launch

```sh
open "$SCRATCH"
```

On first run, add a server pointing at `127.0.0.1`, port `16667`, no TLS, and join
`#textwerk` and `#general` on connect (the mock server ignores authentication, so any
nickname works). This only needs doing once per scratch container — quitting and
reopening the app reconnects automatically.

## 5. Capture

- Resize the main window to **exactly 1920×1080** before capturing. Every shot in
  `images/` and `docs/screenshots/` should be 1920×1080, for consistency across the
  README and the website and to look sharp on retina displays.
- Capture the **window only**, not the full screen — none of the shots should show
  desktop background, the menu bar, or other windows. Get the window ID and use
  `screencapture -o -l<windowID> out.png` (or an equivalent window-targeted
  capture), not a full-screen grab followed by cropping. `screencapture` can't write
  WebP directly, so capture PNG first, then convert (see below).
- For light vs dark shots, toggle **macOS system appearance** (System Settings →
  Appearance) before capturing — not an in-app theme override — since the shots are
  meant to show the OS-level light/dark experience, not just the chat theme.
- For Chat vs Classic IRC shots, toggle **Preferences → Style → Display Style**
  (radio buttons labeled "Chat" and "Classic IRC") before capturing — this is the
  setting added by the Slack-style grouped-message work; "Chat" is the grouped/
  Slack-style default, "Classic IRC" is the traditional one-line-per-message look.
  Capture every shot in **both** styles (see the table below) so we can show off
  both display modes rather than just the default.
- Scroll the channel to a range that reads naturally — the general-conversation
  shots are scrolled near the top of the scrollback, showing the join line, the
  topic, and the first several messages including the media cards, not the very
  bottom.

## 6. Convert to WebP

Screenshots ship as `.webp`, not `.png` — convert right after capturing and delete
the intermediate PNG:

```sh
# brew install webp, if cwebp isn't already available
cwebp -q 90 out.png -o out.webp
```

`-q 90` is a good default: visually near-lossless at a fraction of the PNG size. Bump
it up if a particular shot shows compression artifacts (fine text, sharp UI edges).

## What screenshots we need

Every shot below is needed in **both** Display Style variants — suffix the filename
with `-chat` (Chat/grouped style) or `-classic` (Classic IRC style).

| File (both `-chat` and `-classic` variants) | Branch/path | Size | Shows |
|---|---|---|---|
| `screenshot-light-{chat,classic}.webp` | `images/` (website) | 1920×1080 | `#textwerk`, light appearance, general conversation incl. media cards |
| `screenshot-dark-{chat,classic}.webp` | `images/` (website) | 1920×1080 | Same view, dark appearance |
| `split-view-{chat,classic}.webp` | `images/` (website) | 1920×1080 | Two channels open side by side in split view |
| `direct-message-{chat,classic}.webp` | `images/` (website) | 1920×1080 | The query window with `ashby`, showing the "common channels" info bar |
| `preview-light-general-{chat,classic}.webp` | `docs/screenshots/` (master) | 1920×1080 | Same shot as `screenshot-light-*.webp` |
| `preview-dark-general-{chat,classic}.webp` | `docs/screenshots/` (master) | 1920×1080 | Same shot as `screenshot-dark-*.webp` |

That's 12 files total. Copy the finished WebPs into both locations (they're
identical files, just duplicated across branches) rather than only updating one
side. Once real screenshots exist, `index.html` and the `master` README still only
reference one variant each (`screenshot-light.png` / `preview-light-general.png`) —
decide then whether to show both styles (e.g. a toggle or side-by-side) or just pick
one as the "hero" shot and keep the other variant available for anyone who wants it.
