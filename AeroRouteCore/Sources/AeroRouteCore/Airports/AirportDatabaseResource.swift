import Foundation

/// Location of the immutable airport catalog bundled with AeroRouteCore.
public enum AirportDatabaseResource {
    public static let url: URL = {
        guard let url = Bundle.module.url(
            forResource: "airports",
            withExtension: "sqlite"
        ) else {
            preconditionFailure("AeroRouteCore is missing its bundled airport database")
        }
        return url
    }()
}
