/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
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

import Foundation

@objc(ICMInlineHTMLFoundation)
open class ICMInlineHTMLFoundation: ICLInlineContentModule {
	override open var styleResources: [URL]? {
		Bundle.main.url(forResource: "ICMInlineHTML", withExtension: "css", subdirectory: "Components").map { [$0] }
	}

	override open var scriptResources: [URL]? {
		Bundle.main.url(forResource: "ICMInlineHTML", withExtension: "js", subdirectory: "Components").map { [$0] }
	}

	override open var templateURL: URL? {
		Bundle.main.url(forResource: "ICMInlineHTML", withExtension: "mustache", subdirectory: "Components")
	}

	override open var entrypoint: String? { "_ICMInlineHTML" }
	override open class var contentUntrusted: Bool { true }
}

@objc(ICMInlineHTML)
open class ICMInlineHTML: ICMInlineHTMLFoundation {

	@objc(performActionForHTML:)
	open func performAction(forHTML unescapedHTML: String) {
		let attrs: NSDictionary = [
			"classAttribute": payload.classAttribute,
			"unescapedHTML": unescapedHTML,
			"uniqueIdentifier": payload.uniqueIdentifier
		]
		var renderError: Error? = nil
		let rendered: String?
		do {
			rendered = try template?.renderObject(attrs)
		} catch {
			renderError = error
			rendered = nil
		}
		payload.html = rendered ?? ""
		finalizeWithError(renderError)
	}

	@objc(notifyUnableToPresentHTML)
	open func notifyUnableToPresentHTML() {
		cancel()
	}

	@objc(actionBlockForHTML:)
	open class func actionBlock(forHTML html: String) -> ICLInlineContentModuleActionBlock {
		return { module in
			(module as? ICMInlineHTML)?.performAction(forHTML: html)
		}
	}
}
