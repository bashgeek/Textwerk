/* Defined in: "Textual.app -> Contents -> Resources -> JavaScript -> API -> core.js" */

Textual.viewBodyDidLoad = function()
{
	Textual.fadeOutLoadingScreen(1.00, 0.95);
}

Textual.messageAddedToView = function(line, fromBuffer)
{
	var element = document.getElementById("line-" + line);

	if (element) {
		Textwerk.updateGroupingForLine(element);
	}

	ConversationTracking.updateNicknameWithNewMessage(element);
}

Textual.nicknameSingleClicked = function(e)
{
	ConversationTracking.nicknameSingleClickEventCallback(e);
}

/* Collapses consecutive messages from the same sender into a single
visual group by hiding the repeated sender name (the timestamp is kept,
but dimmed until hover) whenever a message immediately follows another
message from the same person within a short window. Anything that breaks
up the DOM flow between two lines (a date separator, a session marker, a
history gap, etc.) naturally breaks the group, since grouping only looks
at the immediately preceding sibling element. */

var Textwerk = {};

Textwerk.groupableLineTypes = ["privmsg", "action"];

Textwerk.groupingWindow = 5 * 60 * 1000; /* 5 minutes, in milliseconds */

Textwerk.updateGroupingForLine = function(element)
{
	if (Textwerk.groupableLineTypes.indexOf(element.dataset.lineType) === -1) {
		return;
	}

	if (element.dataset.highlight === "true") {
		return;
	}

	var previous = element.previousElementSibling;

	if (!previous || !previous.classList.contains("line")) {
		return;
	}

	if (Textwerk.groupableLineTypes.indexOf(previous.dataset.lineType) === -1) {
		return;
	}

	if (previous.dataset.highlight === "true") {
		return;
	}

	var sender = element.querySelector(".sender");
	var previousSender = previous.querySelector(".sender");

	if (!sender || !previousSender) {
		return;
	}

	if (sender.dataset.nickname !== previousSender.dataset.nickname) {
		return;
	}

	var currentTime = parseFloat(element.dataset.timestamp);
	var previousTime = parseFloat(previous.dataset.timestamp);

	if (isNaN(currentTime) || isNaN(previousTime)) {
		return;
	}

	if ((currentTime - previousTime) * 1000 > Textwerk.groupingWindow) {
		return;
	}

	element.classList.add("grouped");
}
