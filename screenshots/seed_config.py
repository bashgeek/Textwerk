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

What this does and doesn't do:
  - Populates the sidebar with a "MockNet" entry and the #textwerk/#general
    channels, with nickname "daniel_", confirmed to work reliably.
  - Deliberately leaves the actual server address/port unset. Seeding those
    directly (flat serverAddress/serverPort keys, or a nested serverList
    array) either gets silently dropped or -- in one attempt -- caused the
    app to hang on launch with zero windows ever appearing, for reasons not
    fully root-caused. Setting the address via the in-app "Server
    Properties" dialog after launch (Server menu > Server Properties...) is
    the confirmed-reliable path -- its fields are ordinary, scriptable
    AXTextFields/AXComboBox, unlike the wizard's flaky validation.
  - autoConnect is set to YES, but whether that actually triggers a
    connection on launch was never confirmed end-to-end (see README.md).
    Don't rely on it -- select the MockNet row and use Server > Connect
    manually (or automate it the same way) after setting the address.
"""

import plistlib
import os
import sys

MOCK_HOST = "127.0.0.1"
MOCK_PORT = 16667


def seed(bundle_id):
    path = os.path.expanduser(
        f"~/Library/Containers/{bundle_id}/Data/Library/Preferences/group.app.textwerk.plist"
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)

    config = {
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
            }
        ]
    }

    with open(path, "wb") as f:
        plistlib.dump(config, f)

    print(f"wrote {path}")
    print(f"Now set the server address to {MOCK_HOST}:{MOCK_PORT} via Server Properties after first launch.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: seed_config.py <bundle-id>", file=sys.stderr)
        sys.exit(1)

    seed(sys.argv[1])
