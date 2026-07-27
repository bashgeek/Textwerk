/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

#import "ICMInlineHTML.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Common base class for modules that render a lightweight
 icon/title/subtitle card for a link, sourced from a
 provider's own JSON API (oEmbed or similar) rather than
 by scraping the destination page itself.
 */
@interface ICMLinkPreviewCard : ICMInlineHTML

/**
 Renders and inlines a card using the given metadata.

 @param title
  Required. The headline shown in the card.

 @param meta
  Optional short fact shown after the site name on the card's
  subtitle line (e.g. "9 min read", "★ 1,412", "u/someUser").

 @param imageURL
  Optional icon/thumbnail. Ignored if its scheme is not http/https.

 @param siteName
  Optional label identifying the provider (e.g. "github.com").
  Shown on the card's subtitle line, ahead of -meta.

 @param targetURL
  The URL the card links to when clicked. Must be http/https.
 */
- (void)performActionForCardWithTitle:(NSString *)title
								  meta:(nullable NSString *)meta
							  imageURL:(nullable NSURL *)imageURL
							  siteName:(nullable NSString *)siteName
							 targetURL:(NSURL *)targetURL;

/**
 Called by a subclass to indicate that a card cannot be built,
 such as when a provider's API request fails or returns
 nothing usable. Cancels inlining for the payload.
 */
- (void)notifyUnableToPresentCard;

@end

NS_ASSUME_NONNULL_END
