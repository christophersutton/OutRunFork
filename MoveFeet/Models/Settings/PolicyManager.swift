//
//  PolicyManager.swift
//
//  OutRun
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

class PolicyManager {
    
    static let baseURL = "https://move.wavelength.computer/policies/"
    private static let session = URLSession.shared
    
    /// Invalid or unavailable remote documents fall back to the version shipped with this app.
    static func query(for type: PolicyType, completion: @escaping (Bool, Error?, String?) -> Void) {
        var request = URLRequest(url: URL(string: baseURL + type.urlExtension)!)
        request.timeoutInterval = 8
        session.dataTask(with: request) { data, response, error in
            let content = error == nil ? validatedText(data: data, response: response) : nil
            DispatchQueue.main.async {
                completion(true, nil, content ?? type.bundledText)
            }
        }.resume()
    }

    static func validatedText(data: Data?, response: URLResponse?) -> String? {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.mimeType?.lowercased() == "text/plain",
              let data, let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.lowercased().contains("<html"),
              !text.lowercased().contains("<!doctype html") else { return nil }
        return text
    }

    enum PolicyType {
        case termsOfService, privacyPolicy
        
        /// Kept in the executable so privacy information remains available offline.
        var bundledText: String {
            switch self {
            case .privacyPolicy:
                return """
                Move Run — Privacy
                Updated October 21, 2026

                Move Run stores your workouts, routes, measurements and preferences on your device. Recording uses location, including in the background during a workout, and motion data. Apple Maps supplies map content.

                Apple Health integration is optional. When enabled and authorized, Move Run can read workouts and related route, heart-rate, step and weight data, and write workouts and measurements. You control Health access in iOS Settings. Disabling synchronization stops future synchronization; it does not remove records already saved in Apple Health.

                Move Run has no account service, advertising or developer analytics service. The app does not upload your workout history to a developer server. Apple services, device backups and any destinations you choose when sharing exports operate under their own settings and policies. Exported backups and GPX files can contain sensitive location and health information; share them only with recipients you choose.

                You can delete local workouts or all local data in Settings. Local deletion and Apple Health deletion are separate operations. Copies you export or include in device backups may remain until you delete those copies.

                Opening online policy documents contacts move.wavelength.computer; that service receives ordinary web request information such as your IP address. A copy of this information is included in the app for offline use.

                Questions: support@wavelength.computer. If you contact support, include only information you want to share; workout exports are not sent automatically.
                """
            case .termsOfService:
                return """
                Move Run — About use
                Updated October 21, 2026

                Move Run is a personal workout recorder provided by Chris Sutton / Wavelength. Recording, distance, timing and calorie estimates may be incomplete or inaccurate. The app is not a medical device or a source of medical advice. Use your own judgment when exercising and keep backups of history you wish to retain.

                Move Run is a fork of OutRun by Tim Fraedrich. The application is provided under the GNU General Public License version 3 or later, without warranty, to the extent permitted by that license and applicable law. Nothing here limits the rights granted by that license. The license and attribution are included with the project.

                Source and license: https://github.com/christophersutton/OutRunFork
                Support: support@wavelength.computer
                """
            }
        }

        var title: String {
            switch self {
            case .termsOfService:
                return LS["Settings.TermsOfService"]
            case .privacyPolicy:
                return LS["Settings.PrivacyPolicy"]
            }
        }
        
        var urlExtension: String {
            switch self {
            case .termsOfService:
                return "terms-of-service.txt"
            case .privacyPolicy:
                return "privacy-policy.txt"
            }
        }
    }
    
}
