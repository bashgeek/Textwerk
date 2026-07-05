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

// MARK: - ICLMediaAssessment (Immutable)

@objc
open class ICLMediaAssessment: NSObject, NSSecureCoding, NSCopying, NSMutableCopying, @unchecked Sendable {

	// MARK: - Backing Storage

	fileprivate var _url: URL
	fileprivate var _type: ICLMediaType
	fileprivate var _contentType: String
	fileprivate var _contentLength: UInt64

	// MARK: - Read-only Properties

	@objc open var url: URL { _url }
	@objc open var type: ICLMediaType { _type }
	@objc open var contentType: String { _contentType }
	@objc open var contentLength: UInt64 { _contentLength }

	// MARK: - Designated Initializer

	@available(*, unavailable)
	override public init() { fatalError("Use designated initializer") }

	@objc(initWithURL:asType:)
	public init(url: URL, asType type: ICLMediaType) {
		_url = url
		_type = type
		_contentType = "application/binary"
		_contentLength = 0
		super.init()
	}

	// Internal init for copy/decode operations
	fileprivate init(_internalURL url: URL, type: ICLMediaType, contentType: String, contentLength: UInt64) {
		_url = url
		_type = type
		_contentType = contentType
		_contentLength = contentLength
		super.init()
	}

	// MARK: - NSSecureCoding

	@objc public static var supportsSecureCoding: Bool { true }

	@objc public required convenience init?(coder aDecoder: NSCoder) {
		guard let url = aDecoder.decodeObject(of: NSURL.self, forKey: "url") as URL? else {
			return nil
		}
		// ObjC used encodeUnsignedInteger:/decodeUnsignedIntegerForKey: (NSUInteger).
		// In Swift, decodeInteger(forKey:) reads the same encoding on 64-bit platforms.
		let type = ICLMediaType(rawValue: UInt(bitPattern: aDecoder.decodeInteger(forKey: "type"))) ?? .unknown
		let contentType = aDecoder.decodeObject(of: NSString.self, forKey: "contentType") as String? ?? "application/binary"
		let contentLength = UInt64(bitPattern: Int64(aDecoder.decodeInteger(forKey: "contentLength")))

		self.init(_internalURL: url, type: type, contentType: contentType, contentLength: contentLength)
	}

	@objc open func encode(with aCoder: NSCoder) {
		aCoder.encode(_url as NSURL, forKey: "url")
		// ObjC used encodeUnsignedInteger: for both type and contentLength
		aCoder.encode(Int(_type.rawValue), forKey: "type")
		aCoder.encode(_contentType as NSString, forKey: "contentType")
		aCoder.encode(Int(bitPattern: UInt(_contentLength)), forKey: "contentLength")
	}

	// MARK: - NSCopying

	@objc open func copy(with zone: NSZone? = nil) -> Any {
		return ICLMediaAssessment(_internalURL: _url, type: _type, contentType: _contentType, contentLength: _contentLength)
	}

	// MARK: - NSMutableCopying

	@objc open func mutableCopy(with zone: NSZone? = nil) -> Any {
		return ICLMediaAssessmentMutable(_internalURL: _url, type: _type, contentType: _contentType, contentLength: _contentLength)
	}
}

// MARK: - ICLMediaAssessmentMutable

@objc
open class ICLMediaAssessmentMutable: ICLMediaAssessment {

	@objc override open var type: ICLMediaType {
		get { _type }
		set {
			if _type != newValue {
				_type = newValue
			}
		}
	}

	@objc override open var contentType: String {
		get { _contentType }
		set {
			if _contentType != newValue {
				_contentType = newValue
			}
		}
	}

	@objc override open var contentLength: UInt64 {
		get { _contentLength }
		set {
			if _contentLength != newValue {
				_contentLength = newValue
			}
		}
	}

	// NSMutableCopying override — returns another mutable copy
	@objc override open func mutableCopy(with zone: NSZone? = nil) -> Any {
		return ICLMediaAssessmentMutable(_internalURL: _url, type: _type, contentType: _contentType, contentLength: _contentLength)
	}

	// NSCopying — returns immutable copy
	@objc override open func copy(with zone: NSZone? = nil) -> Any {
		return ICLMediaAssessment(_internalURL: _url, type: _type, contentType: _contentType, contentLength: _contentLength)
	}
}
