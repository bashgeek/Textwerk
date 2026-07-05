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

@objc(ICMInlineImageFoundation)
open class ICMInlineImageFoundation: ICLInlineContentModule {
	override open class var contentImageOrVideo: Bool { true }

	override open var templateURL: URL? {
		Bundle.main.url(forResource: "ICMInlineImage", withExtension: "mustache", subdirectory: "Components")
	}

	override open var styleResources: [URL]? {
		Bundle.main.url(forResource: "ICMInlineImage", withExtension: "css", subdirectory: "Components").map { [$0] }
	}

	override open var scriptResources: [URL]? {
		let urls = [
			Bundle.main.url(forResource: "InlineImageLiveResize", withExtension: "js"),
			Bundle.main.url(forResource: "ICMInlineImage", withExtension: "js", subdirectory: "Components")
		].compactMap { $0 }
		return urls.isEmpty ? nil : urls
	}

	override open var entrypoint: String? { "_ICMInlineImage" }
}

@objc(ICMInlineImage)
open class ICMInlineImage: ICMInlineImageFoundation {
	private var imageCheck: ICLMediaAssessor? = nil

	@objc(performAction)
	open func performAction() {
		performAction(withImageCheck: true)
	}

	@objc(performActionWithImageCheck:)
	open func performAction(withImageCheck checkImage: Bool) {
		if checkImage {
			_performImageCheck()
		} else {
			_safeToLoadImage()
		}
	}

	@objc(performActionForURL:)
	open func performAction(forURL url: URL) {
		performAction(forURL: url, bypassImageCheck: false)
	}

	@objc(performActionForURL:bypassImageCheck:)
	open func performAction(forURL url: URL, bypassImageCheck: Bool) {
		precondition(imageCheck == nil, "Module already initialized")
		payload.urlToInline = url
		performAction(withImageCheck: !bypassImageCheck)
	}

	@objc(performActionForAddress:)
	open func performAction(forAddress address: String) {
		performAction(forAddress: address, bypassImageCheck: false)
	}

	@objc(performActionForAddress:bypassImageCheck:)
	open func performAction(forAddress address: String, bypassImageCheck: Bool) {
		guard let url = ICLHelpers.url(withString: address) else { return }
		performAction(forURL: url, bypassImageCheck: bypassImageCheck)
	}

	private func _performImageCheck() {
		let assessor = ICLMediaAssessor.assessor(for: payload.urlToInline, withType: .image) { [weak self] _, error in
			guard let self = self else { return }
			if error == nil {
				self._safeToLoadImage()
			} else {
				self._unsafeToLoadImage()
				if let error = error { ICLMediaAssessor.logError(error as NSError) }
			}
			self.imageCheck = nil
		}
		imageCheck = assessor
		assessor.resume()
	}

	private func _unsafeToLoadImage() {
		notifyUnsafeToLoadImage()
	}

	private func _safeToLoadImage() {
		let attrs: NSDictionary = [
			"anchorLink": payload.address,
			"classAttribute": payload.classAttribute,
			"imageURL": payload.addressToInline,
			"preferredMaximumWidth": TPCPreferences.inlineMediaMaxWidth(),
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

	@objc(notifyUnsafeToLoadImage)
	open func notifyUnsafeToLoadImage() {
		cancel()
	}

	@objc(actionBlockURL:)
	open class func actionBlock(url: URL) -> ICLInlineContentModuleActionBlock {
		return actionBlock(url: url, bypassImageCheck: false)
	}

	@objc(actionBlockURL:bypassImageCheck:)
	open class func actionBlock(url: URL, bypassImageCheck: Bool) -> ICLInlineContentModuleActionBlock {
		return actionBlock(forAddress: url.absoluteString, bypassImageCheck: bypassImageCheck)
	}

	@objc(actionBlockForAddress:)
	open class func actionBlock(forAddress address: String) -> ICLInlineContentModuleActionBlock {
		return actionBlock(forAddress: address, bypassImageCheck: false)
	}

	@objc(actionBlockForAddress:bypassImageCheck:)
	open class func actionBlock(forAddress address: String, bypassImageCheck: Bool) -> ICLInlineContentModuleActionBlock {
		return { module in
			(module as? ICMInlineImage)?.performAction(forAddress: address, bypassImageCheck: bypassImageCheck)
		}
	}
}
