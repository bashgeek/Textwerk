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
import ImageIO

// Hardcoded maximum width for images
private let _assessorMaximumImageWidth: Int = 7200

let ICLMediaAssessorErrorDomain: String = "ICLMediaAssessorErrorDomain"

typealias ICLMediaAssessorCompletionBlock = (ICLMediaAssessment?, NSError?) -> Void

@objc enum ICLMediaAssessorErrorCode: UInt {
	case assessmentFailed = 0
	case unexpectedStatusCode = 1001
	case malformedContentType = 1002
	case malformedContentLength = 1003
	case unexpectedType = 1004
	case unexpectedResponse = 1005
	case contentLengthExceeded = 1006
	case maximumWidthExceeded = 1007
	case maximumHeightExceeded = 1008
}

@objc
final class ICLMediaAssessor: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {

	// MARK: - Configuration Storage (replaces nested ObjC helper classes)

	private var completionBlock: ICLMediaAssessorCompletionBlock?
	private var expectedType: ICLMediaType = .unknown
	private var configURL: URL?

	// Limits
	private var imageMaximumWidth: Int = 0
	private var imageMaximumHeight: Int = 0
	private var imageMaximumFilesize: UInt64 = 0

	// Request state
	private var session: URLSession?
	private var task: URLSessionTask?
	private var alternateError: NSError?
	private var doNotFinalize: Bool = false

	// Assessment state
	private var assessment: ICLMediaAssessment?
	private var performExtendedValidation: Bool = false

	// MARK: - Static cached content type lists

	static let validImageContentTypes: Set<String> = [
		"image/gif",
		"image/jpeg",
		"image/png",
		"image/svg+xml",
		"image/tiff",
		"image/x-ms-bmp"
	]

	static let validVideoContentTypes: Set<String> = [
		"video/3gpp",
		"video/3gpp2",
		"video/mp4",
		"video/quicktime",
		"video/x-m4v"
	]

	// MARK: - Construction

	@available(*, unavailable)
	override init() { fatalError() }

	@objc(assessorForURL:completionBlock:)
	class func assessor(for url: URL, completionBlock: @escaping ICLMediaAssessorCompletionBlock) -> ICLMediaAssessor {
		return assessor(for: url, withType: .unknown, completionBlock: completionBlock)
	}

	@objc(assessorForAddress:completionBlock:)
	class func assessor(forAddress address: String, completionBlock: @escaping ICLMediaAssessorCompletionBlock) -> ICLMediaAssessor {
		return assessor(forAddress: address, withType: .unknown, completionBlock: completionBlock)
	}

	@objc(assessorForURL:withType:completionBlock:)
	class func assessor(for url: URL, withType type: ICLMediaType, completionBlock: @escaping ICLMediaAssessorCompletionBlock) -> ICLMediaAssessor {
		return ICLMediaAssessor(url: url, withType: type, completionBlock: completionBlock)
	}

	@objc(assessorForAddress:withType:completionBlock:)
	class func assessor(forAddress address: String, withType type: ICLMediaType, completionBlock: @escaping ICLMediaAssessorCompletionBlock) -> ICLMediaAssessor {
		let url = URL(string: address)!
		return ICLMediaAssessor(url: url, withType: type, completionBlock: completionBlock)
	}

	private init(url: URL, withType type: ICLMediaType, completionBlock: @escaping ICLMediaAssessorCompletionBlock) {
		super.init()
		prepareToAssess(url: url, type: type, completionBlock: completionBlock)
	}

	private func prepareToAssess(url: URL, type: ICLMediaType, completionBlock: @escaping ICLMediaAssessorCompletionBlock) {
		self.completionBlock = completionBlock
		self.expectedType = type
		self.configURL = url
	}

	// MARK: - Actions (Public)

	@objc func resume() {
		assess()
	}

	@objc func suspend() {
		cancelRequest()
	}

	// MARK: - Actions (Private)

	private func assess() {
		precondition(session == nil, "An assessment is already in progress")

		guard let url = configURL else {
			preconditionFailure("-assess called after an assessment finalized")
		}

		// Create session
		let urlSession = URLSession(configuration: Self.sharedSessionConfiguration, delegate: self, delegateQueue: nil)
		self.session = urlSession

		// We use a data task (always GET). Many services block HEAD requests.
		// When we only need headers, we cancel after receiving them.
		let urlSessionTask = urlSession.dataTask(with: url)
		self.task = urlSessionTask

		// Prepare limits for images
		if expectedType == .unknown || expectedType == .image {
			imageMaximumWidth = _assessorMaximumImageWidth
			imageMaximumHeight = Int(TPCPreferences.inlineMediaMaxHeight())
			imageMaximumFilesize = TPCPreferences.inlineImagesMaxFilesize()
		}

		urlSessionTask.resume()
	}

	private func cancelRequest() {
		doNotFinalize = true
		session?.invalidateAndCancel()
	}

	private func flushRequestState() {
		session = nil
		task = nil
		alternateError = nil
		doNotFinalize = false
		assessment = nil
		performExtendedValidation = false
		imageMaximumWidth = 0
		imageMaximumHeight = 0
		imageMaximumFilesize = 0
	}

	private func finalizeAssessment(error: NSError?) {
		var resolvedError = error

		// If cancelled by us, check if we stored an alternate error
		if let err = resolvedError, err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
			resolvedError = alternateError
		}

		performCompletionBlock(error: resolvedError)
		flushRequestState()
		completionBlock = nil
		configURL = nil
	}

	private func performCompletionBlock(error: NSError?) {
		guard let completionBlock = completionBlock else { return }

		var resolvedError = error

		// This condition is typically true when we refuse an authentication challenge.
		if resolvedError == nil && assessment == nil {
			resolvedError = makeError(description: "Assessment failed", code: .assessmentFailed)
		}

		completionBlock(assessment, resolvedError)
	}

	private func makeError(description: String, code: ICLMediaAssessorErrorCode) -> NSError {
		return NSError(
			domain: ICLMediaAssessorErrorDomain,
			code: Int(code.rawValue),
			userInfo: [NSLocalizedDescriptionKey: description]
		)
	}

	// MARK: - URL Session Configuration

	private static let sharedSessionConfiguration: URLSessionConfiguration = {
		let config = URLSessionConfiguration.ephemeral
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		config.httpShouldSetCookies = false
		config.httpCookieAcceptPolicy = .never
		return config
	}()

	// MARK: - Header Reading

	/// Reads response headers and populates the assessment state.
	/// Sets `alternateError` on failure and returns nil.
	private func _readHeadersIn(from response: HTTPURLResponse) -> (assessment: ICLMediaAssessmentMutable, performExtendedValidation: Bool)? {
		// Check status code
		if response.statusCode != 200 {
			alternateError = makeError(description: "Endpoint did not respond with OK (200)", code: .unexpectedStatusCode)
			return nil
		}

		// Read content type
		guard let contentType = response.mimeType, contentType.count <= 128 else {
			alternateError = makeError(description: "Content-Type header is improperly formatted", code: .malformedContentType)
			return nil
		}

		// Read content length
		let contentLength = response.expectedContentLength
		guard contentLength > 0 else {
			alternateError = makeError(description: "Content-Length header is improperly formatted", code: .malformedContentLength)
			return nil
		}

		// Determine media type
		var mediaType: ICLMediaType = .other
		var doExtendedValidation = false

		if Self.validImageContentTypes.contains(contentType) {
			mediaType = .image
		} else if Self.validVideoContentTypes.contains(contentType) {
			mediaType = .video
		}

		// Check against expected type
		if expectedType != .unknown && expectedType != mediaType {
			alternateError = makeError(description: "Unexpected media type", code: .unexpectedType)
			return nil
		}

		// Basic validation
		switch mediaType {
		case .image:
			if UInt64(contentLength) > imageMaximumFilesize {
				alternateError = makeError(description: "Content-Length exceeds maximum allowed", code: .contentLengthExceeded)
				return nil
			}
			if imageMaximumHeight > 0 {
				doExtendedValidation = true
			}
		default:
			break
		}

		let responseURL = response.url ?? configURL!
		let newAssessment = ICLMediaAssessmentMutable(url: responseURL, asType: mediaType)
		newAssessment.contentType = contentType
		newAssessment.contentLength = UInt64(contentLength)

		return (newAssessment, doExtendedValidation)
	}

	// MARK: - URLSessionDataDelegate

	func urlSession(
		_ session: URLSession,
		dataTask: URLSessionDataTask,
		didReceive response: URLResponse,
		completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
	) {
		guard let httpResponse = response as? HTTPURLResponse else {
			alternateError = makeError(description: "Invalid response type (not HTTP)", code: .unexpectedResponse)
			completionHandler(.cancel)
			return
		}

		guard let result = _readHeadersIn(from: httpResponse) else {
			// alternateError was set inside _readHeadersIn
			completionHandler(.cancel)
			return
		}

		self.assessment = result.assessment
		self.performExtendedValidation = result.performExtendedValidation

		if !result.performExtendedValidation {
			completionHandler(.cancel)
			return
		}

		completionHandler(.becomeDownload)
	}

	func urlSession(
		_ session: URLSession,
		dataTask: URLSessionDataTask,
		willCacheResponse proposedResponse: CachedURLResponse,
		completionHandler: @escaping (CachedURLResponse?) -> Void
	) {
		completionHandler(nil)
	}

	// MARK: - URLSessionTaskDelegate

	func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		willPerformHTTPRedirection response: HTTPURLResponse,
		newRequest request: URLRequest,
		completionHandler: @escaping (URLRequest?) -> Void
	) {
		completionHandler(request)
	}

	func urlSession(
		_ session: URLSession,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		let method = challenge.protectionSpace.authenticationMethod
		if method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest {
			completionHandler(.cancelAuthenticationChallenge, nil)
			return
		}
		completionHandler(.performDefaultHandling, nil)
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		if doNotFinalize {
			flushRequestState()
			return
		}
		finalizeAssessment(error: error as NSError?)
	}

	// MARK: - URLSessionDataDelegate (become download)

	func urlSession(
		_ session: URLSession,
		dataTask: URLSessionDataTask,
		didBecomeDownloadTask downloadTask: URLSessionDownloadTask
	) {
		self.task = downloadTask
	}

	// MARK: - URLSessionDownloadDelegate

	func urlSession(
		_ session: URLSession,
		downloadTask: URLSessionDownloadTask,
		didFinishDownloadingTo location: URL
	) {
		if performExtendedValidation(at: location) {
			return // Success
		}
		session.invalidateAndCancel()
	}

	func urlSession(
		_ session: URLSession,
		downloadTask: URLSessionDownloadTask,
		didWriteData bytesWritten: Int64,
		totalBytesWritten: Int64,
		totalBytesExpectedToWrite: Int64
	) {
		guard !downloadProgressExceededMaximumFilesize(UInt64(max(0, totalBytesWritten))) else {
			alternateError = makeError(description: "Maximum response size exceeded", code: .contentLengthExceeded)
			session.invalidateAndCancel()
			return
		}
	}

	// MARK: - Extended Validation

	private func downloadProgressExceededMaximumFilesize(_ downloadProgress: UInt64) -> Bool {
		var maximumFilesize: UInt64 = 0

		if let type = assessment?.type, type == .image {
			maximumFilesize = imageMaximumFilesize
		}

		guard maximumFilesize > 0 else { return false }
		return downloadProgress > maximumFilesize
	}

	private func performExtendedValidation(at url: URL) -> Bool {
		guard let type = assessment?.type else { return true }

		switch type {
		case .image:
			return performExtendedValidationForImage(at: url)
		default:
			return true
		}
	}

	private func performExtendedValidationForImage(at url: URL) -> Bool {
		guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
			alternateError = makeError(
				description: "Image validation: CGImageSourceCreateWithURL() returned NULL",
				code: .assessmentFailed
			)
			return false
		}

		guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) else {
			alternateError = makeError(
				description: "Image validation: CGImageSourceCopyPropertiesAtIndex() returned NULL",
				code: .assessmentFailed
			)
			return false
		}

		let props = imageProperties as NSDictionary
		let imageWidth = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
		let imageHeight = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0

		if imageWidth > imageMaximumWidth {
			alternateError = makeError(description: "Image validation: Maximum width exceeded", code: .maximumWidthExceeded)
			return false
		}
		if imageHeight > imageMaximumHeight {
			alternateError = makeError(description: "Image validation: Maximum height exceeded", code: .maximumHeightExceeded)
			return false
		}

		return true
	}

	// MARK: - Logging

	@objc static func logError(_ error: NSError) {
		guard error.domain == ICLMediaAssessorErrorDomain else { return }

		let code = ICLMediaAssessorErrorCode(rawValue: UInt(error.code)) ?? .assessmentFailed

		switch code {
		case .assessmentFailed, .unexpectedStatusCode, .malformedContentType, .malformedContentLength, .unexpectedResponse:
			Logging.defaultSubsystem?.debug("Assessor fatal error: \(error.localizedDescription, privacy: .public)")
		case .unexpectedType, .contentLengthExceeded, .maximumWidthExceeded, .maximumHeightExceeded:
			Logging.defaultSubsystem?.debug("Assessor validation error: \(error.localizedDescription, privacy: .public)")
		@unknown default:
			Logging.defaultSubsystem?.debug("Assessor unknown error: \(error.localizedDescription, privacy: .public)")
		}
	}
}
