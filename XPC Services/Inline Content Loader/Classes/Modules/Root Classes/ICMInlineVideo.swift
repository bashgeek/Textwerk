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

/* ICMInlineVideoFoundation does nothing. It exists for internal use. */
@objc(ICMInlineVideoFoundation)
open class ICMInlineVideoFoundation: ICLInlineContentModule {
	@objc open var videoAutoplayEnabled: Bool = false
	@objc open var videoControlsEnabled: Bool = true  // default = YES
	@objc open var videoLoopEnabled: Bool = false
	@objc open var videoMuteEnabled: Bool = false
	@objc open var videoStartTime: TimeInterval = 0
	@objc open var videoPlaybackSpeed: Double = 1.0   // default = 1.0

	override open class var contentImageOrVideo: Bool { true }

	override open var templateURL: URL? {
		Bundle.main.url(forResource: "ICMInlineVideo", withExtension: "mustache", subdirectory: "Components")
	}

	override open var styleResources: [URL]? {
		Bundle.main.url(forResource: "ICMInlineVideo", withExtension: "css", subdirectory: "Components").map { [$0] }
	}

	override open var scriptResources: [URL]? {
		Bundle.main.url(forResource: "ICMInlineVideo", withExtension: "js", subdirectory: "Components").map { [$0] }
	}

	override open var entrypoint: String? { "_ICMInlineVideo" }

	@objc(parseYouTubeEsqueTimestamp:)
	open class func parseYouTubeEsqueTimestamp(_ timestamp: String) -> TimeInterval {
		let ns = timestamp as NSString
		if ns.isPositiveWholeNumber {
			return ns.doubleValue
		}

		var startTime: TimeInterval = 0
		var matchedHour = false
		var matchedMinute = false
		var matchedSecond = false

		ns.enumerateMatches(ofRegularExpression: "[0-9]+[hms]", with: { range, stop in
			let fragment = ns.substring(with: range) as NSString
			// substringAtIndex:0 toLength:(-1) extracts the last character (the unit letter h/m/s)
			// substringAtIndex:(-1) toLength:0 extracts all chars except the last (the number)
			let fragmentUnit = fragment.substring(at: 0, toLength: -1)
			let fragmentValue = fragment.substring(at: -1, toLength: 0) as NSString

			if !matchedHour && fragmentUnit == "h" {
				matchedHour = true
				startTime += TimeInterval(fragmentValue.integerValue * 3600)
			} else if !matchedMinute && fragmentUnit == "m" {
				matchedMinute = true
				startTime += TimeInterval(fragmentValue.integerValue * 60)
			} else if !matchedSecond && fragmentUnit == "s" {
				matchedSecond = true
				startTime += TimeInterval(fragmentValue.integerValue)
			}

			if matchedHour && matchedMinute && matchedSecond {
				stop.pointee = true
			}
		}, options: .caseInsensitive)

		return startTime
	}
}

/* Proper class to subclass if that is your thing. */
@objc(ICMInlineVideo)
open class ICMInlineVideo: ICMInlineVideoFoundation {
	private var videoCheck: ICLMediaAssessor? = nil

	@objc(performAction)
	open func performAction() {
		performAction(withVideoCheck: true)
	}

	@objc(performActionWithVideoCheck:)
	open func performAction(withVideoCheck checkVideo: Bool) {
		if checkVideo {
			_performVideoCheck()
		} else {
			_safeToLoadVideo()
		}
	}

	@objc(performActionForURL:)
	open func performAction(forURL url: URL) {
		performAction(forURL: url, bypassVideoCheck: false)
	}

	@objc(performActionForURL:bypassVideoCheck:)
	open func performAction(forURL url: URL, bypassVideoCheck: Bool) {
		precondition(videoCheck == nil, "Module already initialized")
		payload.urlToInline = url
		performAction(withVideoCheck: !bypassVideoCheck)
	}

	@objc(performActionForAddress:)
	open func performAction(forAddress address: String) {
		performAction(forAddress: address, bypassVideoCheck: false)
	}

	@objc(performActionForAddress:bypassVideoCheck:)
	open func performAction(forAddress address: String, bypassVideoCheck: Bool) {
		guard let url = ICLHelpers.url(withString: address) else { return }
		performAction(forURL: url, bypassVideoCheck: bypassVideoCheck)
	}

	private func _performVideoCheck() {
		let assessor = ICLMediaAssessor.assessor(for: payload.urlToInline, withType: .video) { [weak self] _, error in
			guard let self = self else { return }
			if error == nil {
				self._safeToLoadVideo()
			} else {
				self._unsafeToLoadVideo()
				if let error = error { ICLMediaAssessor.logError(error as NSError) }
			}
			self.videoCheck = nil
		}
		videoCheck = assessor
		assessor.resume()
	}

	private func _unsafeToLoadVideo() {
		notifyUnsafeToLoadVideo()
	}

	private func _safeToLoadVideo() {
		var playbackSpeed = videoPlaybackSpeed
		if playbackSpeed < 0.125 || playbackSpeed > 6.0 {
			playbackSpeed = 1.0
		}

		let attrs: NSDictionary = [
			"anchorLink": payload.address,
			"classAttribute": payload.classAttribute,
			"preferredMaximumWidth": TPCPreferences.inlineMediaMaxWidth(),
			"uniqueIdentifier": payload.uniqueIdentifier,
			"videoAutoplayEnabled": videoAutoplayEnabled,
			"videoControlsEnabled": videoControlsEnabled,
			"videoLoopEnabled": videoLoopEnabled,
			"videoMuteEnabled": videoMuteEnabled,
			"videoPlaybackSpeed": playbackSpeed,
			"videoStartTime": videoStartTime,
			"videoURL": payload.addressToInline
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

	@objc(notifyUnsafeToLoadVideo)
	open func notifyUnsafeToLoadVideo() {
		cancel()
	}

	@objc(actionBlockForForURL:)
	open class func actionBlock(forForURL url: URL) -> ICLInlineContentModuleActionBlock {
		return actionBlock(forForURL: url, bypassVideoCheck: false)
	}

	@objc(actionBlockForForURL:bypassVideoCheck:)
	open class func actionBlock(forForURL url: URL, bypassVideoCheck: Bool) -> ICLInlineContentModuleActionBlock {
		return actionBlock(forAddress: url.absoluteString, bypassVideoCheck: bypassVideoCheck)
	}

	@objc(actionBlockForAddress:)
	open class func actionBlock(forAddress address: String) -> ICLInlineContentModuleActionBlock {
		return actionBlock(forAddress: address, bypassVideoCheck: false)
	}

	@objc(actionBlockForAddress:bypassVideoCheck:)
	open class func actionBlock(forAddress address: String, bypassVideoCheck: Bool) -> ICLInlineContentModuleActionBlock {
		return { module in
			(module as? ICMInlineVideo)?.performAction(forAddress: address, bypassVideoCheck: bypassVideoCheck)
		}
	}
}

/* Subclass for videos that should be treated as GIFs:
 videoAutoplayEnabled = YES, videoControlsEnabled = NO,
 videoLoopEnabled = YES, videoMuteEnabled = YES */
@objc(ICMInlineGifVideo)
open class ICMInlineGifVideo: ICMInlineVideo {

	public required init(payload: ICLPayloadMutable, inProcess process: ICLProcessMain) {
		super.init(payload: payload, inProcess: process)
		videoAutoplayEnabled = true
		videoControlsEnabled = false
		videoLoopEnabled = true
		videoMuteEnabled = true
	}

	public required init(deferredModule module: ICLInlineContentModule) {
		super.init(deferredModule: module)
	}
}
