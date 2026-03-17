import ExpoModulesCore
import Foundation
import UniformTypeIdentifiers
import SSZipArchive

public class ExpoGeoParserModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoGeoParser")
    Events("onParseFeatures")

    Function("detectFileType") { (uri: String) -> [String: Any?] in
      let info = Self.detectFileType(from: uri)
      return [
        "uri": uri,
        "fileName": info.fileName,
        "extension": info.fileExtension,
        "type": info.type,
        "uti": info.utiIdentifier
      ]
    }

    AsyncFunction("parseFile") { (uri: String) throws -> [String: Any] in
      var result = try Self.parseGeoFile(from: uri)
      let features = result.removeValue(forKey: "features") as? [[String: Any]] ?? []

      let batchSize = 200
      var idx = 0
      repeat {
        let end = min(idx + batchSize, features.count)
        self.sendEvent("onParseFeatures", [
          "features": Array(features[idx..<end]),
          "isLast": end >= features.count
        ])
        idx = end
      } while idx < features.count

      return result
    }
  }
}

// MARK: - File-type detection

private extension ExpoGeoParserModule {
  struct DetectedFileInfo {
    let fileName: String?
    let fileExtension: String?
    let type: String
    let utiIdentifier: String?
  }

  static func detectFileType(from uri: String) -> DetectedFileInfo {
    guard let url = URL(string: uri) else {
      return DetectedFileInfo(fileName: nil, fileExtension: nil, type: "unknown", utiIdentifier: nil)
    }
    return detectFileType(from: url)
  }

  static func detectFileType(from url: URL) -> DetectedFileInfo {
    let fileName = url.lastPathComponent.isEmpty ? nil : url.lastPathComponent
    let rawExt = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    let ext = rawExt.isEmpty ? nil : rawExt.lowercased()

    let type: String
    switch ext {
    case "kml":     type = "kml"
    case "kmz":     type = "kmz"
    case "zip":     type = "zip"
    case "geojson": type = "geojson"
    case "json":    type = "json"
    default:        type = "unknown"
    }

    let uti = ext.flatMap { UTType(filenameExtension: $0)?.identifier }
    return DetectedFileInfo(fileName: fileName, fileExtension: ext, type: type, utiIdentifier: uti)
  }
}

// MARK: - Parser dispatcher

private extension ExpoGeoParserModule {
  static func parseGeoFile(from uri: String) throws -> [String: Any] {
    guard let url = URL(string: uri) else {
      throw GeoParserError.invalidURI(uri)
    }

    let info = detectFileType(from: url)

    if info.type == "kmz" || info.type == "zip" {
      return try parseArchive(at: url, sourceType: info.type)
    }

    let data = try Data(contentsOf: url)

    switch info.type {
    case "kml":             return try KMLParser.parse(data: data, sourceType: "kml")
    case "geojson", "json": return try GeoJSONParser.parse(data: data, sourceType: info.type)
    default:                return try sniffAndParse(data: data, sourceType: "unknown")
    }
  }

  static func parseArchive(at url: URL, sourceType: String) throws -> [String: Any] {
    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    guard SSZipArchive.unzipFile(atPath: url.path, toDestination: tmpDir.path) else {
      throw GeoParserError.extractionFailed
    }

    guard let enumerator = FileManager.default.enumerator(at: tmpDir, includingPropertiesForKeys: nil) else {
      throw GeoParserError.noGeoDataFound
    }

    var kmlFiles: [URL] = []
    var geojsonFiles: [URL] = []
    for case let fileURL as URL in enumerator {
      let ext = fileURL.pathExtension.lowercased()
      if ext == "kml"                           { kmlFiles.append(fileURL) }
      else if ext == "geojson" || ext == "json" { geojsonFiles.append(fileURL) }
    }

    if let kmlURL = kmlFiles.first(where: { $0.lastPathComponent.lowercased() == "doc.kml" }) ?? kmlFiles.first {
      return try KMLParser.parse(data: Data(contentsOf: kmlURL), sourceType: sourceType)
    }
    if let gjURL = geojsonFiles.first {
      return try GeoJSONParser.parse(data: Data(contentsOf: gjURL), sourceType: sourceType)
    }

    throw GeoParserError.noGeoDataFound
  }

  static func sniffAndParse(data: Data, sourceType: String) throws -> [String: Any] {
    if data.first == UInt8(ascii: "{") {
      return try GeoJSONParser.parse(data: data, sourceType: sourceType)
    }
    if let prefix = String(data: data.prefix(256), encoding: .utf8),
       prefix.contains("<kml") || prefix.contains("<Placemark") || prefix.contains("<Document") {
      return try KMLParser.parse(data: data, sourceType: sourceType)
    }
    throw GeoParserError.unsupportedFormat
  }
}

// MARK: - Errors

enum GeoParserError: LocalizedError {
  case invalidURI(String)
  case extractionFailed
  case noGeoDataFound
  case unsupportedFormat
  case parseError(String)

  var errorDescription: String? {
    switch self {
    case .invalidURI(let uri): return "Invalid URI: \(uri)"
    case .extractionFailed:    return "Failed to extract archive"
    case .noGeoDataFound:      return "No supported geo data found in archive"
    case .unsupportedFormat:   return "Unsupported or unrecognised file format"
    case .parseError(let msg): return "Parse error: \(msg)"
    }
  }
}
