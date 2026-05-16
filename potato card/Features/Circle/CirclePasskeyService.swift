import AuthenticationServices
import Combine
import Foundation
import UIKit

@MainActor
final class CirclePasskeyService: NSObject, ObservableObject {
    private var registrationContinuation: CheckedContinuation<CirclePasskeyRegistrationResponse, Error>?

    func createRegistration(options: CirclePasskeyRegistrationOptions) async throws -> CirclePasskeyRegistrationResponse {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rp.id)
        let request = provider.createCredentialRegistrationRequest(
            challenge: try Data(base64URLEncoded: options.challenge),
            name: options.user.name,
            userID: try Data(base64URLEncoded: options.user.id)
        )

        return try await withCheckedThrowingContinuation { continuation in
            registrationContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension CirclePasskeyService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            registrationContinuation?.resume(throwing: CircleAPIError.invalidResponse)
            registrationContinuation = nil
            return
        }

        let response = CirclePasskeyRegistrationResponse(
            id: credential.credentialID.base64URLEncodedString(),
            rawId: credential.credentialID.base64URLEncodedString(),
            type: "public-key",
            response: CirclePasskeyRegistrationResponse.Response(
                clientDataJSON: credential.rawClientDataJSON.base64URLEncodedString(),
                attestationObject: credential.rawAttestationObject?.base64URLEncodedString() ?? "",
                transports: []
            ),
            clientExtensionResults: [:]
        )
        registrationContinuation?.resume(returning: response)
        registrationContinuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        registrationContinuation?.resume(throwing: error)
        registrationContinuation = nil
    }
}

extension CirclePasskeyService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension Data {
    init(base64URLEncoded value: String) throws {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base64) else { throw CircleAPIError.invalidResponse }
        self = data
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
