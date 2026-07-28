#!/usr/bin/env python3
"""Seed a scratch Textwerk container with the MockNet server/channels/nickname
mock_ircd.py expects, so a fresh launch skips the "Welcome to Textwerk" wizard
entirely (its Destination field's live validation doesn't play well with
scripted entry -- see screenshots/README.md for the whole story).

Usage:
    python3 seed_config.py <bundle-id>

Run this AFTER deploying the scratch .app (see README.md step 2) and BEFORE
the first launch. It writes directly into the scratch container's defaults
plist, under the same "World Controller Client Configurations" key the app
itself uses to persist the server list.

What this does:
  - Populates the sidebar with a "MockNet" entry pointed at
    127.0.0.1:16667 (mock_ircd.py's address) and the #textwerk/#general
    channels, with nickname "daniel_", and autoConnect on.
  - The serverList entry uses the exact keys IRCServer.m's
    -populateDictionaryValues: reads (serverAddress, serverPort,
    prefersSecuredConnection, uniqueIdentifier). IRCClientConfig.m's
    -initWithDictionary: reads serverList unconditionally, before it even
    looks at dictionaryVersion, so this is picked up on first launch --
    no need to fix the address up afterwards via the Server Properties
    dialog.
  - Forces "DisplayEventInLogView -> Inline Media" on, so the media
    preview cards (YouTube/GitHub/image links in mock_ircd.py's
    conversation) actually render for the screenshots. This is the
    registered default as of master now, but setting it explicitly here
    means the seeder still works right against older builds.
"""

import plistlib
import os
import sys
import uuid

MOCK_HOST = "127.0.0.1"
MOCK_PORT = 16667


def seed(bundle_id):
    path = os.path.expanduser(
        f"~/Library/Containers/{bundle_id}/Data/Library/Preferences/group.app.textwerk.plist"
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)

    config = {
        "DisplayEventInLogView -> Inline Media": True,
        "World Controller Client Configurations": [
            {
                "connectionName": "MockNet",
                "nickname": "daniel_",
                "autoConnect": True,
                "dictionaryVersion": 710,
                "channelList": [
                    {"channelName": "#textwerk"},
                    {"channelName": "#general"},
                ],
                "serverList": [
                    {
                        "serverAddress": MOCK_HOST,
                        "serverPort": MOCK_PORT,
                        "prefersSecuredConnection": False,
                        "uniqueIdentifier": str(uuid.uuid4()),
                    }
                ],
            }
        ]
    }

    with open(path, "wb") as f:
        plistlib.dump(config, f)

    print(f"wrote {path}")
    print(f"MockNet server list points at {MOCK_HOST}:{MOCK_PORT} -- should autoConnect on launch.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: seed_config.py <bundle-id>", file=sys.stderr)
        sys.exit(1)

    seed(sys.argv[1])
