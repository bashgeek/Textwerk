#!/usr/bin/env python3
"""Minimal single-client mock IRCd for taking Textwerk screenshots.
Not a general-purpose server - assumes exactly one client connects,
supports just enough of the protocol (CAP/WHOX/multi-prefix/extended-join)
to populate a realistic-looking window."""

import asyncio
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 16667
SERVER_NAME = "mock.textwerk.dev"
NETWORK = "MockNet"

CAPS = [
    "multi-prefix",
    "account-notify",
    "extended-join",
    "server-time",
    "batch",
    "echo-message",
    "chghost",
    "userhost-in-names",
    "cap-notify",
    "away-notify",
    "message-tags",
    "draft/typing",
]

# nick -> (prefix, account-or-None, ident, host)
CHANNEL_USERS = {
    "#textwerk": {
        "daniel_": ("~", "daniel_", "d", "d.mockcloud.net"),
        "alice": ("@", "alice", "alice", "alice.mockcloud.net"),
        "bob": ("@", None, "bob", "bob.users.mock"),
        "carol": ("%", "carol", "carol", "carol.staff.mock"),
        "dave": ("+", None, "dave", "dave.users.mock"),
        "erin": ("+", None, "erin", "erin.users.mock"),
        "frank": ("", "frank", "frank", "frank.users.mock"),
        "grace": ("", None, "grace", "grace.users.mock"),
        "heidi": ("", None, "heidi", "heidi.users.mock"),
        "ivan": ("", None, "ivan", "ivan.users.mock"),
        "judy": ("", None, "judy", "judy.users.mock"),
    },
    "#general": {
        "daniel_": ("", "daniel_", "d", "d.mockcloud.net"),
        "alice": ("@", "alice", "alice", "alice.mockcloud.net"),
        "mallory": ("+", None, "mallory", "mallory.users.mock"),
        "trent": ("", None, "trent", "trent.users.mock"),
        "peggy": ("", "peggy", "peggy", "peggy.staff.mock"),
    },
}

CHANNEL_TOPICS = {
    "#textwerk": "Textwerk development - IRCv3 modernization pass | https://github.com/bashgeek/Textwerk",
    "#general": "general chit-chat",
}

QUERY_NICK = "ashby"
QUERY_HOST = ("ashby", "ashby.mockcloud.net")


def now_tag():
    t = time.gmtime()
    return time.strftime("%Y-%m-%dT%H:%M:%S.000Z", t)


class Client:
    def __init__(self, reader, writer):
        self.reader = reader
        self.writer = writer
        self.nick = None
        self.registered = False
        self.caps_requested = set()
        self.negotiating = False

    def send(self, line, tag_time=False):
        if tag_time:
            line = f"@time={now_tag()} {line}"
        self.writer.write((line + "\r\n").encode("utf-8", "replace"))

    async def drain(self):
        await self.writer.drain()

    def send_numeric(self, code, *params, trailing=None):
        target = self.nick or "*"
        parts = [f":{SERVER_NAME}", code, target, *params]
        line = " ".join(parts)
        if trailing is not None:
            line += f" :{trailing}"
        self.send(line)

    async def handle(self):
        while True:
            raw = await self.reader.readline()
            if not raw:
                return
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            if not line:
                continue
            try:
                await self.dispatch(line)
            except Exception as exc:
                print(f"!! error dispatching {line!r}: {exc}", flush=True)
            await self.drain()

    async def dispatch(self, line):
        print(f"<< {line}", flush=True)
        tags = {}
        if line.startswith("@"):
            tag_str, line = line.split(" ", 1)
            for pair in tag_str[1:].split(";"):
                if "=" in pair:
                    k, v = pair.split("=", 1)
                    tags[k] = v
                else:
                    tags[pair] = True
        parts = line.split(" ")
        cmd = parts[0].upper()

        if cmd == "TAGMSG":
            target = parts[1] if len(parts) > 1 else "?"
            print(f"   (parsed TAGMSG target={target} tags={tags})", flush=True)
            return

        if cmd == "CAP":
            sub = parts[1].upper() if len(parts) > 1 else ""
            if sub == "LS":
                self.negotiating = True
                self.send(f":{SERVER_NAME} CAP * LS :{' '.join(CAPS)}")
            elif sub == "REQ":
                rest = line.split(" ", 2)[2] if len(parts) > 2 else ""
                if rest.startswith(":"):
                    rest = rest[1:]
                requested = rest.split()
                granted = [c for c in requested if c.lstrip("-") in CAPS]
                self.caps_requested.update(c for c in granted if not c.startswith("-"))
                self.send(f":{SERVER_NAME} CAP * ACK :{' '.join(requested)}")
            elif sub == "END":
                self.negotiating = False
                await self.maybe_register()
        elif cmd == "NICK":
            self.nick = parts[1]
            await self.maybe_register()
        elif cmd == "USER":
            self.username = parts[1]
            await self.maybe_register()
        elif cmd == "PASS":
            pass
        elif cmd == "PING":
            token = parts[1] if len(parts) > 1 else "0"
            self.send(f":{SERVER_NAME} PONG {SERVER_NAME} {token}")
        elif cmd == "PONG":
            pass
        elif cmd == "JOIN":
            channel = parts[1].split(",")[0]
            await self.join_channel(channel)
        elif cmd == "WHO":
            channel = parts[1]
            whox = len(parts) > 2
            await self.who_reply(channel, whox)
        elif cmd == "MODE":
            pass
        elif cmd == "PRIVMSG":
            await self.handle_privmsg(parts, line)
        else:
            pass

    async def maybe_register(self):
        if self.registered or self.negotiating or self.nick is None:
            return
        if not hasattr(self, "username"):
            return
        self.registered = True
        self.send_numeric("001", trailing=f"Welcome to the {NETWORK} mock network, {self.nick}")
        self.send_numeric("002", trailing=f"Your host is {SERVER_NAME}")
        self.send_numeric("003", trailing="This server was created just now")
        self.send_numeric("004", SERVER_NAME, "mockircd-1.0", "iowghraAsORTVSxNCWqBzvdHtGpI", "lvhopsmntikrRcaqOALQbSeIKVfMCuzNTGjZ")
        self.send_numeric(
            "005",
            "PREFIX=(qaohv)~&@%+",
            "CHANTYPES=#",
            "CHANMODES=beI,k,l,imnpstQ",
            "NETWORK=" + NETWORK,
            "CASEMAPPING=rfc1459",
            "WHOX",
            "NICKLEN=30",
            "CHANNELLEN=50",
            trailing="are supported by this server",
        )
        self.send_numeric("376", trailing="End of /MOTD command.")
        asyncio.create_task(self.post_registration())

    async def post_registration(self):
        await asyncio.sleep(0.3)
        for channel in CHANNEL_USERS:
            await self.join_channel(channel, server_initiated=True)
            await asyncio.sleep(0.15)
        await asyncio.sleep(0.3)
        asyncio.create_task(self.simulate_activity())
        asyncio.create_task(self.simulate_query())
        asyncio.create_task(self.simulate_typing())

    async def join_channel(self, channel, server_initiated=False):
        users = CHANNEL_USERS.get(channel)
        if users is None:
            return
        self.send(f":{self.nick}!{getattr(self, 'username', 'u')}@mock.local JOIN {channel}")
        self.send_numeric("332", channel, trailing=CHANNEL_TOPICS.get(channel, ""))
        self.send_numeric("333", channel, "alice", str(int(time.time()) - 86400))
        names = []
        for nick, (prefix, account, ident, host) in users.items():
            names.append(f"{prefix}{nick}")
        self.send_numeric("353", "=", channel, trailing=" ".join(names))
        self.send_numeric("366", channel, trailing="End of /NAMES list.")

    async def who_reply(self, channel, whox):
        users = CHANNEL_USERS.get(channel)
        if users is None:
            self.send_numeric("315", channel, trailing="End of /WHO list.")
            return
        for nick, (prefix, account, ident, host) in users.items():
            flags = "H" + prefix
            acct = account if account else "0"
            if whox:
                self.send_numeric(
                    "354", "152", channel, ident, host, nick, flags, acct,
                    trailing=f"{nick} real name",
                )
            else:
                self.send_numeric(
                    "352", channel, ident, host, SERVER_NAME, nick, flags,
                    trailing=f"0 {nick} real name",
                )
        self.send_numeric("315", channel, trailing="End of /WHO list.")

    async def handle_privmsg(self, parts, raw_line):
        target = parts[1]
        text = raw_line.split(" ", 2)[2].lstrip(":") if len(parts) > 2 else ""
        if target.lower() == QUERY_NICK:
            return
        # echo not needed; server doesn't need to relay to a fake channel

    def relay(self, nick, ident, host, target, text, action=False):
        if action:
            text = f"\x01ACTION {text}\x01"
        self.send(f":{nick}!{ident}@{host} PRIVMSG {target} :{text}", tag_time=True)

    def send_typing(self, nick, ident, host, target, state):
        self.send(f"@+typing={state} :{nick}!{ident}@{host} TAGMSG {target}")

    async def simulate_typing(self):
        await asyncio.sleep(2.0)

        people = {
            "heidi": CHANNEL_USERS["#textwerk"]["heidi"],
            "grace": CHANNEL_USERS["#textwerk"]["grace"],
        }

        # (nicks typing during this phase, how long to hold it) -- cycles
        # through nobody -> one -> two -> one -> nobody so the indicator's
        # appear/vanish and 1-vs-2-person states all get exercised, not
        # just a permanent "two people typing".
        phases = [
            (set(), 4.0),
            ({"heidi"}, 3.5),
            ({"heidi", "grace"}, 4.0),
            ({"grace"}, 3.0),
            (set(), 5.0),
            ({"grace"}, 3.0),
            ({"heidi", "grace"}, 3.5),
            ({"heidi"}, 3.0),
            (set(), 6.0),
        ]

        refresh_interval = 2.5  # real clients resend "active" periodically
        currently_typing = set()

        while True:
            for typing_now, duration in phases:
                for nick in currently_typing - typing_now:
                    info = people[nick]
                    self.send_typing(nick, info[2], info[3], "#textwerk", "done")
                    print(f">> {nick} stopped typing in #textwerk", flush=True)

                currently_typing = typing_now

                elapsed = 0.0
                while elapsed < duration:
                    if currently_typing:
                        for nick in currently_typing:
                            info = people[nick]
                            self.send_typing(nick, info[2], info[3], "#textwerk", "active")
                        names = " + ".join(sorted(currently_typing))
                        print(f">> simulating {names} typing in #textwerk (active)", flush=True)

                    step = min(refresh_interval, duration - elapsed)
                    await asyncio.sleep(step)
                    elapsed += step

    async def simulate_activity(self):
        seq = [
            ("#textwerk", "alice", "morning all"),
            ("#textwerk", "carol", "morning! how was the weekend"),
            ("#textwerk", "alice", "good, mostly just relaxed"),
            ("#textwerk", "bob", "same here, needed it"),
            ("#textwerk", "dave", f"{self.nick}: hey have you seen this yet? https://www.youtube.com/watch?v=aqz-KE-bpKQ"),
            ("#textwerk", "erin", "haha yeah that's a classic"),
            ("#textwerk", "frank", "reminds me, here's that repo I mentioned earlier https://github.com/torvalds/linux"),
            ("#textwerk", "grace", "oh nice, bookmarking that"),
            ("#textwerk", "heidi", "found this earlier lol https://www.gstatic.com/webp/gallery/1.jpg"),
            ("#textwerk", "ivan", "lmao"),
            ("#textwerk", "judy", "anyway, back to it"),
            ("#textwerk", "bob", "yeah same, talk later"),
            ("#general", "peggy", "standup in 5 btw"),
            ("#general", "trent", "omw"),
            ("#general", "mallory", "one sec, grabbing coffee"),
        ]
        for channel, nick, text in seq:
            info = CHANNEL_USERS[channel][nick]
            self.relay(nick, info[2], info[3], channel, text)
            await asyncio.sleep(0.25)

    async def simulate_query(self):
        await asyncio.sleep(0.5)
        self.relay(QUERY_NICK, QUERY_HOST[0], QUERY_HOST[1], self.nick,
                   "hey, got a sec?")
        await asyncio.sleep(0.6)
        self.relay(QUERY_NICK, QUERY_HOST[0], QUERY_HOST[1], self.nick,
                   "wanted to ask about the meetup next week")


async def handle_client(reader, writer):
    peer = writer.get_extra_info("peername")
    print(f"connection from {peer}", flush=True)
    client = Client(reader, writer)
    try:
        await client.handle()
    except (ConnectionResetError, BrokenPipeError):
        pass
    finally:
        writer.close()


async def main():
    server = await asyncio.start_server(handle_client, "127.0.0.1", PORT)
    print(f"mock ircd listening on 127.0.0.1:{PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
