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

/* Checks every URL to determine if it is an
 image or video, then delegates responsibility
 for the module to an instance of a root class. */

import Foundation

@objc
class ICMAssessedMedia: ICLInlineContentModule {
	private var mediaAssessor: ICLMediaAssessor? = nil

	@objc private func _assessMedia() {
		let assessor = ICLMediaAssessor.assessor(for: payload.url, completionBlock: { [weak self] assessment, error in
			guard let self = self else { return }
			let type: ICLMediaType = assessment?.type ?? .unknown
			let safeToLoad = assessment != nil && error == nil && ICLInlineContentModule.isTypeDeferrable(type)
			if safeToLoad, let assessment = assessment {
				self._safeToLoadMedia(ofType: type, at: assessment.url)
			} else {
				self._unsafeToLoadMedia()
			}
			self.mediaAssessor = nil
		})
		self.mediaAssessor = assessor
		assessor.resume()
	}

	private func _unsafeToLoadMedia() {
		cancel()
	}

	private func _safeToLoadMedia(ofType type: ICLMediaType, at url: URL) {
		payload.urlToInline = url
		deferAsType(type, performCheck: false)
	}

	@objc(actionForURL:)
	override class func action(for url: URL) -> Selector? {
		guard TPCPreferences.inlineMediaCheckEverything() else { return nil }
		return #selector(_assessMedia)
	}

	override class var contentImageOrVideo: Bool { true }
	override class var contentIsFile: Bool { true }
}
