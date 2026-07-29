/* Defined in: "Textual.app -> Contents -> Resources -> JavaScript -> API -> core.js" */

/* Nickname colors.

The app's built-in generator (IRCUserNicknameColorStyleGenerator) hashes a
nickname to a point in HSL space spanning all 360 hues at lightness 45-81%.
Against this theme's backgrounds that produces two problems: the dark end of
its range bottoms out around 2.7:1 contrast on 13px bold text, and because
nothing enforces a minimum hue separation, small channels routinely land
three or four nicknames in the same yellow-green band.

Textwerk replaces it with a fixed 14-color palette, generated in OKLCh at
constant perceptual lightness so entries are evenly spaced in hue and every
one clears 4.5:1 against its own background. The palette lives in each
variety's design.css as --nick-01 ... --nick-14 rather than here, so Light
and Dark can ship different values while sharing this file. */

var TextwerkNicknameColors = (function() {
	'use strict';

	var paletteSize = 14;

	var palette = null;
	var selfColor = null;

	function readPalette()
	{
		if (palette !== null) {
			return;
		}

		var styles = window.getComputedStyle(document.documentElement);

		palette = [];

		for (var i = 1; i <= paletteSize; i++) {
			var name = "--nick-" + (i < 10 ? "0" : "") + i;

			var value = styles.getPropertyValue(name).trim();

			if (value.length > 0) {
				palette.push(value);
			}
		}

		selfColor = styles.getPropertyValue("--nick-self").trim();
	}

	/* djb2, computed here rather than through app.nicknameColorStyleHash().
	That call is an asynchronous bridge into native code, and the line is
	already in the document by the time messageAddedToView() runs, so an
	async recolor can let the app's own color paint first and flicker. A
	synchronous hash cannot. */
	function hashOfString(text)
	{
		var hash = 5381;

		for (var i = 0; i < text.length; i++) {
			hash = ((hash << 5) + hash) ^ text.charCodeAt(i);
		}

		/* Final mix: the palette index is taken modulo 14, and djb2's low
		bits alone are weakly distributed for small even moduli. */
		hash ^= (hash >>> 15);

		return (hash >>> 0);
	}

	/* Fold the conventional "same person, different session" decorations
	together so that alice, alice_ and alice|away share one color. */
	function normalizeNickname(nickname)
	{
		return nickname.toLowerCase()
					   .replace(/\|.*$/, "")
					   .replace(/[`_\-\[\]{}\\^]+$/, "");
	}

	/* Hashing alone picks the slot; these resolve the collisions it leaves
	behind. A hash of 14 slots is uniform in aggregate but says nothing
	about any one channel: 10 people in a room land on 7 distinct colors
	on average, and three of them sharing one color is entirely ordinary.
	Since telling speakers apart is the whole point, a nickname whose slot
	is already spoken for probes forward to the next free one and keeps it
	for the lifetime of the view.

	The cost is that a color is stable per view rather than globally -- the
	same person can be a different color in two channels. That is the right
	side of the trade: color here is a within-conversation cue, and a hash
	that is stable everywhere but ambiguous where it is read is stable in
	the wrong place. */
	var assignedColors = {};
	var claimedSlots = {};

	function colorForNickname(nickname)
	{
		readPalette();

		if (palette.length === 0) {
			return null;
		}

		var key = normalizeNickname(nickname);

		/* A nickname made up entirely of decoration (e.g. "___") normalizes
		to nothing, which would collapse every such nickname onto one color. */
		if (key.length === 0) {
			key = nickname.toLowerCase();
		}

		if (assignedColors.hasOwnProperty(key)) {
			return assignedColors[key];
		}

		var preferredSlot = hashOfString(key) % palette.length;

		var slot = preferredSlot;

		for (var i = 0; i < palette.length; i++) {
			var candidate = (preferredSlot + i) % palette.length;

			if (claimedSlots.hasOwnProperty(candidate) === false) {
				slot = candidate;

				break;
			}
		}

		/* Every slot taken means the view has more distinct speakers than
		the palette has colors, at which point sharing is unavoidable and
		the loop above falls through to the hashed slot. */
		claimedSlots[slot] = key;

		assignedColors[key] = palette[slot];

		return assignedColors[key];
	}

	/* An empty inline color means the user turned nickname colorizing off in
	preferences, in which case the template omits the style attribute and the
	theme has no business adding one back. */
	function isColorizable(element)
	{
		return (element.dataset.overrideColor !== "true" &&
				element.style.color !== "");
	}

	/* Sender labels carry data-member-type="myself", but nicknames matched
	inside message text do not — so without knowing who you are, a mention of
	you renders in a palette color while your own sender label two lines up
	renders in --nick-self. Cached because the lookup is an async bridge into
	native code and this is consulted for every inline nickname. */
	var localNickname = null;

	function refreshLocalNickname()
	{
		if (typeof app === "undefined" || app.localUserNickname === undefined) {
			return;
		}

		app.localUserNickname(function(nickname) {
			localNickname = (nickname ? normalizeNickname(nickname) : null);
		});
	}

	function isLocalNickname(nickname)
	{
		return (localNickname !== null &&
				normalizeNickname(nickname) === localNickname);
	}

	function applyToLine(line)
	{
		if (line === null) {
			return;
		}

		var lineType = line.dataset.lineType;

		if (lineType !== "privmsg" && lineType !== "action") {
			return;
		}

		readPalette();

		var sender = line.querySelector(".sender");

		if (sender !== null && isColorizable(sender)) {
			if (sender.dataset.memberType === "myself") {
				/* The template writes the generated color into a style
				attribute, which outranks any stylesheet rule. design.css
				therefore cannot express "this one is you" on its own — that
				has to be applied here or not at all. */
				if (selfColor.length > 0) {
					sender.style.color = selfColor;
				}
			} else {
				var senderColor = colorForNickname(sender.dataset.nickname || sender.textContent);

				if (senderColor !== null) {
					sender.style.color = senderColor;
				}
			}
		}

		/* Nicknames matched inside message text carry their own copy of the
		generated color and have to be recolored to stay consistent with the
		sender labels above them. */
		var inlineSenders = line.querySelectorAll(".inlineSender");

		for (var i = 0; i < inlineSenders.length; i++) {
			var inlineSender = inlineSenders[i];

			if (isColorizable(inlineSender) === false) {
				continue;
			}

			var nickname = inlineSender.textContent;

			var userModeSymbol = (inlineSender.dataset.mode || "");

			if (userModeSymbol.length > 0 && nickname.indexOf(userModeSymbol) === 0) {
				nickname = nickname.substring(userModeSymbol.length);
			}

			nickname = nickname.trim();

			if (nickname.length === 0) {
				continue;
			}

			var inlineColor = (isLocalNickname(nickname) && selfColor.length > 0)
							? selfColor
							: colorForNickname(nickname);

			if (inlineColor !== null) {
				inlineSender.style.color = inlineColor;
			}
		}
	}

	return {
		applyToLine: applyToLine,
		refreshLocalNickname: refreshLocalNickname
	};
})();

Textual.viewBodyDidLoad = function()
{
	Textual.fadeOutLoadingScreen(1.00, 0.95);
}

Textual.viewInitiated = function()
{
	TextwerkNicknameColors.refreshLocalNickname();
}

/* Your nickname can change without a NICK command — connecting to a bouncer
that holds a different one, for instance — so both events have to refresh it. */
Textual.handleEvent = function(event)
{
	if (event === "nicknameChanged" || event === "serverConnected") {
		TextwerkNicknameColors.refreshLocalNickname();
	}
}

/* Consecutive-message grouping ("Slack-style" message display) is
decided server-side by -[TVCLogController renderLogLine:previousLine:resultInfo:]
based on the "Message Display" preference, and rendered directly as the
data-grouped="true" attribute on the line element. See design.css for
the corresponding [data-grouped="true"] styling. */

Textual.messageAddedToView = function(line, fromBuffer)
{
	var element = document.getElementById("line-" + line);

	TextwerkNicknameColors.applyToLine(element);

	ConversationTracking.updateNicknameWithNewMessage(element);
}

Textual.nicknameSingleClicked = function(e)
{
	ConversationTracking.nicknameSingleClickEventCallback(e);
}
