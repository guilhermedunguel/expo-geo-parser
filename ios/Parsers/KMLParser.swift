import Foundation

final class KMLParser: NSObject, XMLParserDelegate {

  private var features: [[String: Any]] = []
  private var documentName = ""
  private var documentDescription = ""
  private var styles: [String: StyleInfo] = [:]
  private var styleMaps: [String: String] = [:]

  private var elementStack: [String] = []
  private var textBuffer = ""

  private var documentDepth = 0
  private var documentMetaCaptured = false

  private var inPlacemark = false
  private var currentFeatureId: String?
  private var currentFeatureName = ""
  private var currentFeatureDescription = ""
  private var currentFeatureStyleUrl = ""
  private var currentExtendedData: [String: Any] = [:]
  private var currentExtendedDataName = ""
  private var inExtendedData = false
  private var currentGeometryType: String?

  private var pointCoord: [Double] = []
  private var lineCoords: [[Double]] = []
  private var currentRing: [[Double]] = []
  private var outerRing: [[Double]] = []
  private var innerRings: [[[Double]]] = []
  private var inOuterBoundary = false
  private var inInnerBoundary = false

  private var inMultiGeometry = false
  private var multiGeometries: [[String: Any]] = []

  private var currentStyleId: String?
  private var buildingStyle = StyleInfo()
  private var inLineStyle = false
  private var inPolyStyle = false
  private var inIconStyle = false
  private var inIconHref = false

  private var inStyleMap = false
  private var currentStyleMapId: String?
  private var inPair = false
  private var currentPairKey = ""
  private var currentPairStyleUrl = ""

  static func parse(data: Data, sourceType: String) throws -> [String: Any] {
    let delegate = KMLParser()
    let xmlParser = XMLParser(data: data)
    xmlParser.delegate = delegate
    xmlParser.shouldProcessNamespaces = true
    xmlParser.shouldReportNamespacePrefixes = false

    guard xmlParser.parse() else {
      throw GeoParserError.parseError(xmlParser.parserError?.localizedDescription ?? "XML parse error")
    }

    var result: [String: Any] = [
      "type": "FeatureCollection",
      "sourceType": sourceType,
      "features": delegate.features
    ]
    if !delegate.documentName.isEmpty        { result["name"]        = delegate.documentName }
    if !delegate.documentDescription.isEmpty { result["description"] = delegate.documentDescription }
    return result
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName _: String?,
    attributes attributeDict: [String: String]
  ) {
    let name = stripped(elementName)
    elementStack.append(name)
    textBuffer = ""

    switch name {
    case "Document":        documentDepth += 1
    case "Style":           currentStyleId = attributeDict["id"]; buildingStyle = StyleInfo()
    case "StyleMap":        inStyleMap = true; currentStyleMapId = attributeDict["id"]
    case "Pair":            if inStyleMap { inPair = true; currentPairKey = ""; currentPairStyleUrl = "" }
    case "LineStyle":       inLineStyle = true
    case "PolyStyle":       inPolyStyle = true
    case "IconStyle":       inIconStyle = true
    case "Icon":            if inIconStyle { inIconHref = true }
    case "Placemark":
      inPlacemark = true
      currentFeatureId = attributeDict["id"]
      currentFeatureName = ""
      currentFeatureDescription = ""
      currentFeatureStyleUrl = ""
      currentExtendedData = [:]
      currentExtendedDataName = ""
      inExtendedData = false
      currentGeometryType = nil
      multiGeometries = []
    case "ExtendedData":
      if inPlacemark { inExtendedData = true }
    case "Data", "SimpleData":
      if inPlacemark && inExtendedData { currentExtendedDataName = attributeDict["name"] ?? "" }
    case "Point":           currentGeometryType = "Point";      pointCoord = []
    case "LineString":      currentGeometryType = "LineString"; lineCoords = []
    case "LinearRing":      currentRing = []
    case "Polygon":
      currentGeometryType = "Polygon"
      outerRing = []; innerRings = []
      inOuterBoundary = false; inInnerBoundary = false
    case "MultiGeometry":   inMultiGeometry = true; multiGeometries = []
    case "outerBoundaryIs": inOuterBoundary = true;  inInnerBoundary = false
    case "innerBoundaryIs": inInnerBoundary = true; inOuterBoundary = false
    default: break
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    textBuffer += string
  }

  func parser(_ parser: XMLParser, foundCDATA block: Data) {
    if let s = String(data: block, encoding: .utf8) { textBuffer += s }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName _: String?
  ) {
    let name = stripped(elementName)
    let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
    let parent = elementStack.dropLast().last ?? ""
    defer { textBuffer = ""; if !elementStack.isEmpty { elementStack.removeLast() } }

    switch name {
    case "Document":    documentDepth -= 1
    case "name":
      if inPlacemark && parent == "Placemark" { currentFeatureName = text }
      else if isCollectionContainer(parent) && !documentMetaCaptured { documentName = text; documentMetaCaptured = true }
    case "description":
      if inPlacemark && parent == "Placemark" { currentFeatureDescription = text }
      else if isCollectionContainer(parent) && documentDescription.isEmpty { documentDescription = text }
    case "ExtendedData":
      inExtendedData = false
    case "Data":
      currentExtendedDataName = ""
    case "value":
      if inPlacemark && inExtendedData && !currentExtendedDataName.isEmpty {
        currentExtendedData[currentExtendedDataName] = parsePropertyValue(text)
      }
    case "SimpleData":
      if inPlacemark && inExtendedData && !currentExtendedDataName.isEmpty {
        currentExtendedData[currentExtendedDataName] = parsePropertyValue(text)
      }
      currentExtendedDataName = ""
    case "Style":
      if let id = currentStyleId { styles[id] = buildingStyle }
      currentStyleId = nil
    case "StyleMap":    inStyleMap = false; currentStyleMapId = nil
    case "Pair":
      if inStyleMap && currentPairKey == "normal", let mapId = currentStyleMapId {
        styleMaps[mapId] = currentPairStyleUrl
      }
      inPair = false
    case "key":         if inStyleMap && inPair { currentPairKey = text }
    case "styleUrl":
      if inPlacemark { currentFeatureStyleUrl = text }
      else if inStyleMap && inPair { currentPairStyleUrl = text }
    case "LineStyle":   inLineStyle = false
    case "PolyStyle":   inPolyStyle = false
    case "IconStyle":   inIconStyle = false
    case "Icon":        inIconHref = false
    case "color":
      let hex = kmlColorToCSS(text)
      if inLineStyle { buildingStyle.strokeColor = hex }
      else if inPolyStyle { buildingStyle.fillColor = hex }
    case "width":       if inLineStyle, let w = Double(text) { buildingStyle.strokeWidth = w }
    case "fill":        if inPolyStyle { buildingStyle.fillEnabled = (text != "0") }
    case "href":        if inIconHref { buildingStyle.iconUrl = text }
    case "scale":       if inIconStyle, let s = Double(text) { buildingStyle.iconScale = s }
    case "coordinates":
      let coords = parseCoordinates(text)
      switch parent {
      case "Point":      pointCoord = coords.first ?? []
      case "LineString": lineCoords = coords
      case "LinearRing": currentRing = coords
      default: break
      }
    case "LinearRing":
      if inOuterBoundary { outerRing = currentRing }
      else if inInnerBoundary { innerRings.append(currentRing) }
    case "outerBoundaryIs": inOuterBoundary = false
    case "innerBoundaryIs": inInnerBoundary = false
    case "Point", "LineString", "Polygon":
      if inMultiGeometry, let geom = buildGeometry(type: name) {
        multiGeometries.append(geom)
        pointCoord = []; lineCoords = []; outerRing = []; innerRings = []
      }
    case "MultiGeometry":   inMultiGeometry = false; currentGeometryType = "MultiGeometry"
    case "Placemark":       finalizeFeature(); inPlacemark = false
    default: break
    }
  }

  private func stripped(_ name: String) -> String {
    if let r = name.range(of: ":", options: .backwards) { return String(name[r.upperBound...]) }
    return name
  }

  private func isCollectionContainer(_ name: String) -> Bool {
    name == "Document" || name == "Folder"
  }

  private func kmlColorToCSS(_ kml: String) -> String {
    let s = kml.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard s.count == 8 else { return "#000000" }
    return "#\(s.dropFirst(6).prefix(2))\(s.dropFirst(4).prefix(2))\(s.dropFirst(2).prefix(2))"
  }

  private func parseCoordinates(_ text: String) -> [[Double]] {
    text
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .compactMap { tuple -> [Double]? in
        let parts = tuple.split(separator: ",").compactMap { Double($0) }
        return parts.count >= 2 ? Array(parts) : nil
      }
  }

  private func parsePropertyValue(_ text: String) -> Any {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercased = trimmed.lowercased()

    if lowercased == "true" { return true }
    if lowercased == "false" { return false }
    if isNumericScalar(trimmed), let number = Double(trimmed) {
      return number
    }

    return trimmed
  }

  private func isNumericScalar(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return text.range(of: #"^-?(0|[1-9]\d*)(\.\d+)?$"#, options: .regularExpression) != nil
  }

  private func buildGeometry(type: String) -> [String: Any]? {
    switch type {
    case "Point":
      guard !pointCoord.isEmpty else { return nil }
      return ["type": "Point", "coordinates": pointCoord]
    case "LineString":
      guard !lineCoords.isEmpty else { return nil }
      return ["type": "LineString", "coordinates": lineCoords]
    case "Polygon":
      guard !outerRing.isEmpty else { return nil }
      return ["type": "Polygon", "coordinates": [outerRing] + innerRings]
    default:
      return nil
    }
  }

  private func resolveStyle(url: String) -> StyleInfo? {
    let id = url.hasPrefix("#") ? String(url.dropFirst()) : url
    if let style = styles[id] { return style }
    if let normalUrl = styleMaps[id] {
      let nid = normalUrl.hasPrefix("#") ? String(normalUrl.dropFirst()) : normalUrl
      return styles[nid]
    }
    return nil
  }

  private func finalizeFeature() {
    var properties: [String: Any] = [:]
    if !currentFeatureName.isEmpty { properties["name"] = currentFeatureName }
    for (key, value) in currentExtendedData {
      properties[key] = value
    }

    if !currentFeatureDescription.isEmpty {
      let extracted = extractDescriptionAttributes(from: currentFeatureDescription)
      for (key, value) in extracted.attributes where properties[key] == nil {
        properties[key] = value
      }
      if let description = extracted.description {
        properties["description"] = description
      }
    }

    if !currentFeatureStyleUrl.isEmpty {
      properties["styleId"] = currentFeatureStyleUrl
      if let style = resolveStyle(url: currentFeatureStyleUrl), !style.isEmpty {
        properties["style"] = style.asDictionary()
      }
    }

    let geometries: [[String: Any]]
    if currentGeometryType == "MultiGeometry" {
      guard !multiGeometries.isEmpty else { return }
      geometries = multiGeometries
    } else if let gType = currentGeometryType, let geom = buildGeometry(type: gType) {
      geometries = [geom]
    } else {
      return
    }

    for (index, geometry) in geometries.enumerated() {
      var feature: [String: Any] = ["type": "Feature", "geometry": geometry, "properties": properties]
      if let id = splitFeatureId(baseId: currentFeatureId, index: index, total: geometries.count) {
        feature["id"] = id
      }
      features.append(feature)
    }
  }

  private func splitFeatureId(baseId: String?, index: Int, total: Int) -> String? {
    guard let baseId, !baseId.isEmpty else { return nil }
    guard total > 1 else { return baseId }
    return "\(baseId)_\(index + 1)"
  }

  private func extractDescriptionAttributes(from description: String) -> (attributes: [String: Any], description: String?) {
    let textDescription = stripHTML(description)
    guard description.contains("<table"), description.contains("<th"), description.contains("<td") else {
      return ([:], textDescription.isEmpty ? nil : textDescription)
    }

    guard let regex = try? NSRegularExpression(
      pattern: #"<th[^>]*>\s*(.*?)\s*</th>\s*<td[^>]*>\s*(.*?)\s*</td>"#,
      options: [.caseInsensitive, .dotMatchesLineSeparators]
    ) else {
      return ([:], textDescription.isEmpty ? nil : textDescription)
    }

    let nsDescription = description as NSString
    let matches = regex.matches(in: description, range: NSRange(location: 0, length: nsDescription.length))

    var attributes: [String: Any] = [:]
    for match in matches where match.numberOfRanges >= 3 {
      let key = stripHTML(nsDescription.substring(with: match.range(at: 1)))
      if key.isEmpty { continue }
      let value = stripHTML(nsDescription.substring(with: match.range(at: 2)))
      attributes[key] = parsePropertyValue(value)
    }

    let cleanedDescription: String?
    if !textDescription.isEmpty && !(matches.isEmpty == false && textDescription == "Attributes") {
      cleanedDescription = textDescription
    } else {
      cleanedDescription = nil
    }

    return (attributes, cleanedDescription)
  }

  private func stripHTML(_ value: String) -> String {
    value
      .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private struct StyleInfo {
  var strokeColor: String?
  var strokeWidth: Double?
  var fillColor: String?
  var fillEnabled: Bool = true
  var iconUrl: String?
  var iconScale: Double?

  var isEmpty: Bool { strokeColor == nil && fillColor == nil && iconUrl == nil }

  func asDictionary() -> [String: Any] {
    var d: [String: Any] = [:]
    if let v = strokeColor { d["strokeColor"] = v }
    if let v = strokeWidth { d["strokeWidth"] = v }
    if let v = fillColor   { d["fillColor"]   = v }
    if !fillEnabled        { d["fillEnabled"] = false }
    if let v = iconUrl     { d["iconUrl"]     = v }
    if let v = iconScale   { d["iconScale"]   = v }
    return d
  }
}
