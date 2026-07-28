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
public final class ICLHelpers: NSObject {

	@objc(URLWithString:)
	public class func url(withString address: String) -> URL? {
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
	public class var genericValidationFailedError: NSError {
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

// MARK: - Response Cache

/* Every module's oEmbed/Open Graph lookup goes through -requestJSONData:,
 -requestJSONArray:, or -requestHTML: below, keyed by the exact request URL
 (which already includes any per-item query parameters, e.g. a video ID) --
 caching at that single point covers every provider without touching them.
 Without this, re-rendering a message (scrollback reload, theme switch, a
 WebKit reload triggered by a window resize) re-fetches from the network
 every time, which is both slow and a source of flakiness if the provider
 is briefly rate-limiting or slow to respond. Bounded in both size and time
 so it can't grow unboundedly over a long-running session or serve stale
 metadata forever. */
private final class ICLResponseCache: @unchecked Sendable {
	static let shared = ICLResponseCache()

	private let lock = NSLock()
	private var entries: [URL: (data: Data, expiresAt: Date)] = [:]

	private let timeToLive: TimeInterval = 30 * 60 // 30 minutes
	private let maximumEntries = 200

	func data(for url: URL) -> Data? {
		lock.lock()
		defer { lock.unlock() }

		guard let entry = entries[url] else { return nil }

		if entry.expiresAt < Date() {
			entries.removeValue(forKey: url)
			return nil
		}

		return entry.data
	}

	func setData(_ data: Data, for url: URL) {
		lock.lock()
		defer { lock.unlock() }

		if entries.count >= maximumEntries, entries[url] == nil {
			if let oldestKey = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
				entries.removeValue(forKey: oldestKey)
			}
		}

		entries[url] = (data, Date().addingTimeInterval(timeToLive))
	}
}

extension ICLHelpers {
	/* Shared by every method below: fetches raw response data for a URL,
	 consulting/populating the cache above. Only successful (200 + body)
	 responses are cached -- a failure should be retried next time, not
	 remembered as permanent, in case it was transient. */
	fileprivate class func cachedDataRequest(
		from url: URL,
		completionBlock: @escaping (Data?) -> Void
	) -> URLSessionDataTask {
		if let cachedData = ICLResponseCache.shared.data(for: url) {
			DispatchQueue.global().async {
				completionBlock(cachedData)
			}
			return URLSession.shared.dataTask(with: url) // Inert placeholder; never resumed.
		}

		let task = URLSession.shared.dataTask(with: url) { data, response, error in
			guard let data = data,
				  let httpResponse = response as? HTTPURLResponse,
				  httpResponse.statusCode == 200 else {
				if let error = error {
					Logging.defaultSubsystem?.error("Request failed with error: \(error.localizedDescription, privacy: .public)")
				}
				completionBlock(nil)
				return
			}

			ICLResponseCache.shared.setData(data, for: url)
			completionBlock(data)
		}
		task.resume()
		return task
	}
}

// MARK: - JSON

extension ICLHelpers {

	@discardableResult
	@objc(requestJSONObject:ofType:inHierarchy:fromURL:completionBlock:)
	public class func requestJSONObject(
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
	public class func requestJSONObject(
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
	public class func requestJSONData(
		from url: URL,
		completionBlock: @escaping (Bool, [String: Any]?) -> Void
	) -> URLSessionDataTask {
		return cachedDataRequest(from: url) { data in
			guard let data = data else {
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
	}

	@discardableResult
	@objc(requestJSONDataFromAddress:completionBlock:)
	public class func requestJSONData(
		fromAddress address: String,
		completionBlock: @escaping (Bool, [String: Any]?) -> Void
	) -> URLSessionDataTask {
		let url = URL(string: address)!
		return requestJSONData(from: url, completionBlock: completionBlock)
	}

	/* Same as requestJSONDataFromURL:, but for endpoints (e.g. Vimeo's
	 legacy video API) that respond with a top-level JSON array instead
	 of an object. */
	@discardableResult
	@objc(requestJSONArrayFromURL:completionBlock:)
	public class func requestJSONArray(
		from url: URL,
		completionBlock: @escaping (Bool, [[String: Any]]?) -> Void
	) -> URLSessionDataTask {
		return cachedDataRequest(from: url) { data in
			guard let data = data else {
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

			guard let array = decoded as? [[String: Any]] else {
				completionBlock(false, nil)
				return
			}

			completionBlock(true, array)
		}
	}
}

// MARK: - HTML

extension ICLHelpers {

	@discardableResult
	@objc(requestHTMLFromURL:completionBlock:)
	public class func requestHTML(
		from url: URL,
		completionBlock: @escaping (String?) -> Void
	) -> URLSessionDataTask {
		return cachedDataRequest(from: url) { data in
			guard let data = data, let html = String(data: data, encoding: .utf8) else {
				completionBlock(nil)
				return
			}

			completionBlock(html)
		}
	}

	/* Providers like Twitch don't offer a public, unauthenticated metadata
	 API (their real API requires an OAuth app token) but do render normal
	 Open Graph meta tags server-side, the same tags Slack/Discord/etc. use
	 for their own link previews -- so this reads those directly instead. */
	@objc(openGraphContentForProperty:inHTML:)
	public class func openGraphContent(for property: String, inHTML html: String) -> String? {
		let escapedProperty = NSRegularExpression.escapedPattern(for: property)
		let patterns = [
			"<meta[^>]+property=[\"']\(escapedProperty)[\"'][^>]+content=[\"']([^\"']*)[\"']",
			"<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+property=[\"']\(escapedProperty)[\"']"
		]

		let nsHTML = html as NSString
		let fullRange = NSRange(location: 0, length: nsHTML.length)

		for pattern in patterns {
			guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
			guard let match = regex.firstMatch(in: html, range: fullRange), match.numberOfRanges == 2 else { continue }
			return nsHTML.substring(with: match.range(at: 1)).decodingHTMLEntities()
		}

		return nil
	}

	/* Twitter/X's oEmbed response has no separate plain-text field for the
	 tweet body -- it's embedded in the "html" field's first <p> tag,
	 alongside markup for hashtags/links/media that a compact card doesn't
	 need. */
	@objc(firstParagraphPlainTextFromHTML:)
	public class func firstParagraphPlainText(fromHTML html: String) -> String? {
		guard let regex = try? NSRegularExpression(pattern: "<p[^>]*>(.*?)</p>", options: [.dotMatchesLineSeparators]) else {
			return nil
		}

		let nsHTML = html as NSString
		guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)), match.numberOfRanges == 2 else {
			return nil
		}

		return plainText(fromHTML: nsHTML.substring(with: match.range(at: 1)))
	}

	@objc(plainTextFromHTML:)
	public class func plainText(fromHTML html: String) -> String {
		let nsHTML = html as NSString
		let fullRange = NSRange(location: 0, length: nsHTML.length)

		guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
			return html
		}

		let stripped = regex.stringByReplacingMatches(in: html, range: fullRange, withTemplate: "")

		return stripped.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

private extension String {
	func decodingHTMLEntities() -> String {
		let entities: [(String, String)] = [
			("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
			("&lt;", "<"), ("&gt;", ">"), ("&mdash;", "—"), ("&ndash;", "–"), ("&nbsp;", " ")
		]

		var result = self
		for (entity, replacement) in entities {
			result = result.replacingOccurrences(of: entity, with: replacement)
		}
		return result
	}
}

// MARK: - NSString extension

@objc
extension NSString {
	public func isDomain(_ domain: String) -> Bool {
		return isEqual(to: domain)
	}

	public func isDomainOrSubdomain(_ domain: String) -> Bool {
		return isEqual(to: domain) || hasSuffix("." + domain)
	}
}
