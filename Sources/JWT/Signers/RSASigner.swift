import CTLS
import Crypto

public enum HashMethod {
    case sha256
    case sha384
    case sha512
}

extension HashMethod {
    var type: Int32 {
        switch self {
        case .sha256: return NID_sha256
        case .sha384: return NID_sha384
        case .sha512: return NID_sha512
        }
    }

    var method: Hash.Method {
        switch self {
        case .sha256: return .sha256
        case .sha384: return .sha384
        case .sha512: return .sha512
        }
    }
}

typealias CRSAKey = UnsafeMutablePointer<RSA>

enum RSAKey {
    case `public`(CRSAKey)
    case `private`(CRSAKey)

    public init(_ rawKey: Bytes) throws {
        guard let rsa = rawKey.withUnsafeBufferPointer({ rawKeyPointer -> RSAKey? in
            var base = rawKeyPointer.baseAddress
            let count = rawKey.count

            if let cPrivateKey = d2i_RSAPrivateKey(nil, &base, count) {
                return .private(cPrivateKey)
            } else if let cPublicKey = d2i_RSA_PUBKEY(nil, &base, count) {
                return .public(cPublicKey)
            } else {
                return nil
            }
        }) else {
            throw JWTError.createKey
        }

        self = rsa
    }

    var cKey: CRSAKey {
        switch self {
        case .public(let cKey):
            return cKey
        case .private(let cKey):
            return cKey
        }
    }
}

public final class RS256: RSASigner {
    let key: RSAKey
    let hashMethod = HashMethod.sha256

    init(rsaKey: RSAKey) {
        self.key = rsaKey
    }

    deinit {
        switch key {
        case .public(let key), .private(let key):
            RSA_free(key)
        }
    }
}

public final class RS384: RSASigner {
    let key: RSAKey
    let hashMethod = HashMethod.sha384

    init(rsaKey: RSAKey) {
        self.key = rsaKey
    }

    deinit {
        switch key {
        case .public(let key), .private(let key):
            RSA_free(key)
        }
    }
}

public final class RS512: RSASigner {
    let key: RSAKey
    let hashMethod = HashMethod.sha512

    init(rsaKey: RSAKey) {
        self.key = rsaKey
    }

    deinit {
        switch key {
        case .public(let key), .private(let key):
            RSA_free(key)
        }
    }
}

protocol RSASigner: Signer, BytesInitializable {
    var key: RSAKey { get }
    var hashMethod: HashMethod { get }
    init(rsaKey: RSAKey) throws
}

extension RSASigner {
    public init(bytes: Bytes) throws {
        try self.init(key: bytes)
    }
}

extension RSASigner {
    public init(key: Bytes) throws {
        try self.init(rsaKey: try RSAKey(key))
    }
}

extension RSASigner {
    public func sign(message: Bytes) throws -> Bytes {
        guard case .private(let cKey) = key else {
            throw JWTError.privateKeyRequired
        }

        var siglen: UInt32 = 0
        var sig = Bytes(
            repeating: 0,
            count: Int(RSA_size(cKey))
        )

        let digest = try Hash(hashMethod.method, message).hash()

        let ret = RSA_sign(
            hashMethod.type,
            digest,
            UInt32(digest.count),
            &sig,
            &siglen,
            cKey
        )

        guard ret == 1 else {
            let reason: UnsafeMutablePointer<Int8>? = nil
            ERR_error_string(ERR_get_error(), reason)
            if let reason = reason {
                let string = String(validatingUTF8: reason) ?? ""
                print("[JWT] Signing error: \(string)")
            }
            throw JWTError.signing
        }

        return sig
    }

    public func verify(signature: Bytes, message: Bytes) throws {
        let digest = try Hash(hashMethod.method, message).hash()

        let result = RSA_verify(
            hashMethod.type,
            digest,
            UInt32(digest.count),
            signature,
            UInt32(signature.count),
            key.cKey
        )

        guard result == 1 else {
            throw JWTError.signatureVerificationFailed
        }
    }
}
