/* Defined in: "Textual.app -> Contents -> Resources -> JavaScript -> API -> core.js" */

Textual.viewBodyDidLoad = function()
{
	Textual.fadeOutLoadingScreen(1.00, 0.95);
}

/* Consecutive-message grouping ("Slack-style" message display) is
decided server-side by -[TVCLogController renderLogLine:previousLine:resultInfo:]
based on the "Message Display" preference, and rendered directly as the
data-grouped="true" attribute on the line element. See design.css for
the corresponding [data-grouped="true"] styling. */

Textual.messageAddedToView = function(line, fromBuffer)
{
	var element = document.getElementById("line-" + line);

	ConversationTracking.updateNicknameWithNewMessage(element);
}

Textual.nicknameSingleClicked = function(e)
{
	ConversationTracking.nicknameSingleClickEventCallback(e);
}
