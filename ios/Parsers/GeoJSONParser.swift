import Foundation

struct GeoJSONParser {

  static func parse(data: Data, sourceType: String) throws -> [String: Any] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw GeoParserError.parseError("Invalid JSON")
    }

    let features = extractFeatures(from: json)

    var result: [String: Any] = ["type": "FeatureCollection", "sourceType": sourceType, "features": features]
    if let name = json["name"] as? String { result["name"] = name }
    if let props = json["properties"] as? [String: Any] {
      if let name = props["name"] as? String        { result["name"]        = name }
      if let desc = props["description"] as? String { result["description"] = desc }
    }
    return result
  }

  private static func extractFeatures(from json: [String: Any]) -> [[String: Any]] {
    guard let type = json["type"] as? String else { return [] }

    switch type {
    case "FeatureCollection":
      return (json["features"] as? [[String: Any]] ?? []).compactMap { parseFeature($0) }
    case "Feature":
      return parseFeature(json).map { [$0] } ?? []
    default:
      if isGeometryType(type), let feature = bareGeometryToFeature(json) { return [feature] }
      return []
    }
  }

  private static func parseFeature(_ json: [String: Any]) -> [String: Any]? {
    guard json["type"] as? String == "Feature",
          let geometry = json["geometry"] as? [String: Any]
    else { return nil }

    let properties = json["properties"] as? [String: Any] ?? [:]
    var feature: [String: Any] = ["type": "Feature", "geometry": geometry, "properties": properties]
    if let id = json["id"] { feature["id"] = "\(id)" }
    return feature
  }

  private static func bareGeometryToFeature(_ json: [String: Any]) -> [String: Any]? {
    guard json["type"] as? String != nil else { return nil }
    return ["type": "Feature", "geometry": json, "properties": [:] as [String: Any]]
  }

  private static func isGeometryType(_ type: String) -> Bool {
    let types: Set<String> = [
      "Point", "LineString", "Polygon",
      "MultiPoint", "MultiLineString", "MultiPolygon",
      "GeometryCollection"
    ]
    return types.contains(type)
  }
}
