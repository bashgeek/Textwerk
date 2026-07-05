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
import os.log

@objc(ICLHelpers)
final class ICLHelpers: NSObject {

	@objc(URLWithString:)
	class func url(withString address: String) -> URL? {
		var resolved = address
		if resolved.hasPrefix("//") {
			resolved = "https:" + resolved
		}
		return URL(string: resolved)
	}
}

// MARK: - Errors

extension ICLHelpers {

	@objc
	class var genericValidationFailedError: NSError {
		struct Static {
			nonisolated(unsafe) static let error = NSError(
				domain: "ICLInlineContentErrorDomain",
				code: 1003,
				userInfo: [NSLocalizedDescriptionKey: "Validation failed"]
			)
		}
		return Static.error
	}
}

// MARK: - JSON

extension ICLHelpers {

	@discardableResult
	@objc(requestJSONObject:ofType:inHierarchy:fromURL:completionBlock:)
	class func requestJSONObject(
		_ objectKey: String,
		ofType objectType: AnyClass,
		inHierarchy hierarchy: [String]?,
		from url: URL,
		completionBlock: @escaping (Any?) -> Void
	) -> URLSessionDataTask {
		return requestJSONData(from: url) { success, data in
			guard success, let data = data else {
				completionBlock(nil)
				return
			}

			// Traverse hierarchy
			var currentContext: [String: Any] = data

			if let hierarchy = hierarchy {
				for hierarchyKey in hierarchy {
					guard let next = currentContext[hierarchyKey] as? [String: Any] else {
						completionBlock(nil)
						return
					}
					currentContext = next
				}
			}

			// Get object value and check type
			let objectValue = currentContext[objectKey]

			guard let value = objectValue, type(of: value) == objectType || (value as AnyObject).isKind(of: objectType) else {
				completionBlock(nil)
				return
			}

			completionBlock(value)
		}
	}

	@discardableResult
	@objc(requestJSONObject:ofType:inHierarchy:fromAddress:completionBlock:)
	class func requestJSONObject(
		_ objectKey: String,
		ofType objectType: AnyClass,
		inHierarchy hierarchy: [String]?,
		fromAddress address: String,
		completionBlock: @escaping (Any?) -> Void
	) -> URLSessionDataTask {
		let url = URL(string: address)!
		return requestJSONObject(objectKey, ofType: objectType, inHierarchy: hierarchy, from: url, completionBlock: completionBlock)
	}

	@discardableResult
	@objc(requestJSONDataFromURL:completionBlock:)
	class func requestJSONData(
		from url: URL,
		completionBlock: @escaping (Bool, [String: Any]?) -> Void
	) -> URLSessionDataTask {
		let task = URLSession.shared.dataTask(with: url) { data, response, error in
			guard let data = data,
				  let httpResponse = response as? HTTPURLResponse,
				  httpResponse.statusCode == 200 else {
				if let error = error {
					Logging.defaultSubsystem?.error("Request failed with error: \(error.localizedDescription, privacy: .public)")
				}
				completionBlock(false, nil)
				return
			}

			let decoded: Any
			do {
				decoded = try JSONSerialization.jsonObject(with: data, options: [])
			} catch {
				Logging.defaultSubsystem?.error("Failed to decode response: \(error.localizedDescription, privacy: .public)")
				completionBlock(false, nil)
				return
			}

			guard let dict = decoded as? [String: Any] else {
				completionBlock(false, nil)
				return
			}

			completionBlock(true, dict)
		}
		task.resume()
		return task
	}

	@discardableResult
	@objc(requestJSONDataFromAddress:completionBlock:)
	class func requestJSONData(
		fromAddress address: String,
		completionBlock: @escaping (Bool, [String: Any]?) -> Void
	) -> URLSessionDataTask {
		let url = URL(string: address)!
		return requestJSONData(from: url, completionBlock: completionBlock)
	}
}

// MARK: - NSString extension

@objc
extension NSString {
	func isDomain(_ domain: String) -> Bool {
		return isEqual(to: domain)
	}

	func isDomainOrSubdomain(_ domain: String) -> Bool {
		return isEqual(to: domain) || hasSuffix("." + domain)
	}
}
