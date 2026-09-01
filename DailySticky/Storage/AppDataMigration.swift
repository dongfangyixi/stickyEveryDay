import Foundation
import CoreFoundation

struct AppDataMigrationStep {
    let sourceVersion: Int
    let destinationVersion: Int
    private let transform: ([String: Any]) throws -> [String: Any]

    init(
        sourceVersion: Int,
        destinationVersion: Int,
        transform: @escaping ([String: Any]) throws -> [String: Any]
    ) {
        self.sourceVersion = sourceVersion
        self.destinationVersion = destinationVersion
        self.transform = transform
    }

    func migrate(_ document: [String: Any]) throws -> [String: Any] {
        try transform(document)
    }
}

struct AppDataMigrationResult {
    let appData: AppData
    let sourceVersion: Int
    let migratedData: Data?

    var didMigrate: Bool {
        migratedData != nil
    }
}

struct AppDataMigrationPlan {
    let currentVersion: Int
    private let steps: [AppDataMigrationStep]

    init(currentVersion: Int, steps: [AppDataMigrationStep]) {
        self.currentVersion = currentVersion
        self.steps = steps
    }

    func prepare(_ rawData: Data) throws -> AppDataMigrationResult {
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: rawData)
        } catch {
            throw AppDataMigrationError.invalidJSON(error)
        }

        guard var document = jsonObject as? [String: Any] else {
            throw AppDataMigrationError.invalidRoot
        }

        let sourceVersion = try schemaVersion(in: document)
        guard sourceVersion <= currentVersion else {
            throw AppDataMigrationError.newerSchema(
                found: sourceVersion,
                supported: currentVersion
            )
        }

        var version = sourceVersion
        while version < currentVersion {
            let matchingSteps = steps.filter { $0.sourceVersion == version }
            guard matchingSteps.count <= 1 else {
                throw AppDataMigrationError.duplicateStep(from: version)
            }
            guard let step = matchingSteps.first else {
                throw AppDataMigrationError.missingStep(from: version)
            }
            guard step.destinationVersion == version + 1 else {
                throw AppDataMigrationError.invalidStep(
                    from: step.sourceVersion,
                    to: step.destinationVersion
                )
            }

            document = try step.migrate(document)
            let migratedVersion = try schemaVersion(in: document)
            guard migratedVersion == step.destinationVersion else {
                throw AppDataMigrationError.invalidStepOutput(
                    expected: step.destinationVersion,
                    found: migratedVersion
                )
            }
            version = migratedVersion
        }

        let preparedData: Data
        do {
            preparedData = try JSONSerialization.data(
                withJSONObject: document,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw AppDataMigrationError.invalidMigratedDocument(error)
        }

        let decodedAppData: AppData
        do {
            decodedAppData = try AppDataJSONCodec.decode(preparedData)
        } catch {
            throw AppDataMigrationError.couldNotDecodeCurrentSchema(error)
        }

        guard decodedAppData.schemaVersion == currentVersion else {
            throw AppDataMigrationError.invalidStepOutput(
                expected: currentVersion,
                found: decodedAppData.schemaVersion
            )
        }

        let appData: AppData
        let migratedData: Data?
        if sourceVersion == currentVersion {
            appData = decodedAppData
            migratedData = nil
        } else {
            let canonicalData = try AppDataJSONCodec.encode(decodedAppData)
            appData = try AppDataJSONCodec.decode(canonicalData)
            migratedData = canonicalData
        }

        return AppDataMigrationResult(
            appData: appData,
            sourceVersion: sourceVersion,
            migratedData: migratedData
        )
    }

    private func schemaVersion(in document: [String: Any]) throws -> Int {
        guard let rawVersion = document["schemaVersion"] else {
            return 0
        }
        guard let number = rawVersion as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded() == number.doubleValue,
              number.intValue >= 0
        else {
            throw AppDataMigrationError.invalidSchemaVersion
        }
        return number.intValue
    }
}

extension AppDataMigrationPlan {
    static let production = AppDataMigrationPlan(
        currentVersion: AppData.currentSchemaVersion,
        steps: [
            AppDataMigrationStep(sourceVersion: 0, destinationVersion: 1) { document in
                var migrated = document
                migrated["schemaVersion"] = 1
                return migrated
            },
            AppDataMigrationStep(sourceVersion: 1, destinationVersion: 2) { document in
                var migrated = document
                guard var settings = migrated["settings"] as? [String: Any] else {
                    throw AppDataMigrationError.missingSettings
                }

                settings.setDefault("yellow", forKey: "theme")
                settings.setDefault("english", forKey: "language")
                settings.setDefault(1.0, forKey: "noteOpacity")
                settings.setDefault(false, forKey: "hasSeenWelcome")
                settings.setDefault("localOnly", forKey: "storageMode")
                settings.setDefault(false, forKey: "hasChosenStorageMode")
                settings.setDefault(1.0, forKey: "noteZoom")

                migrated["settings"] = settings
                migrated["schemaVersion"] = 2
                return migrated
            }
        ]
    )
}

private extension Dictionary where Key == String, Value == Any {
    mutating func setDefault(_ value: Any, forKey key: String) {
        if self[key] == nil {
            self[key] = value
        }
    }
}

enum AppDataMigrationError: LocalizedError {
    case invalidJSON(Error)
    case invalidRoot
    case invalidSchemaVersion
    case newerSchema(found: Int, supported: Int)
    case missingStep(from: Int)
    case duplicateStep(from: Int)
    case invalidStep(from: Int, to: Int)
    case invalidStepOutput(expected: Int, found: Int)
    case missingSettings
    case invalidMigratedDocument(Error)
    case couldNotDecodeCurrentSchema(Error)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let error):
            return "The data file is not valid JSON: \(error.localizedDescription)"
        case .invalidRoot:
            return "The data file must contain a JSON object at its root."
        case .invalidSchemaVersion:
            return "The data file has an invalid schema version."
        case .newerSchema(let found, let supported):
            return "The data file uses schema version \(found), but this version of Pinaday supports up to version \(supported)."
        case .missingStep(let version):
            return "No migration is registered for schema version \(version)."
        case .duplicateStep(let version):
            return "More than one migration is registered for schema version \(version)."
        case .invalidStep(let source, let destination):
            return "The migration from version \(source) to version \(destination) is not sequential."
        case .invalidStepOutput(let expected, let found):
            return "A migration produced schema version \(found) instead of \(expected)."
        case .missingSettings:
            return "The data file is missing its settings object."
        case .invalidMigratedDocument(let error):
            return "The migrated data could not be encoded: \(error.localizedDescription)"
        case .couldNotDecodeCurrentSchema(let error):
            return "The migrated data does not match the current schema: \(error.localizedDescription)"
        }
    }
}

enum AppDataJSONCodec {
    static func encode(_ appData: AppData) throws -> Data {
        try encoder.encode(appData)
    }

    static func decode(_ data: Data) throws -> AppData {
        try decoder.decode(AppData.self, from: data)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalISO8601Formatter.string(from: date))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = iso8601Formatter.date(from: string)
                ?? fractionalISO8601Formatter.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date string."
            )
        }
        return decoder
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
