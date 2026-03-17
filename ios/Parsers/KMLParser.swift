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
      currentGeometryType = nil
      multiGeometries = []
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
    defer { textBuffer = ""; if !elementStack.isEmpty { elementStack.removeLast() } }

    switch name {
    case "Document":    documentDepth -= 1
    case "name":
      if inPlacemark { currentFeatureName = text }
      else if documentDepth > 0 && !documentMetaCaptured { documentName = text; documentMetaCaptured = true }
    case "description":
      if inPlacemark { currentFeatureDescription = text }
      else if documentDepth > 0 && documentDescription.isEmpty { documentDescription = text }
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
      let parent = elementStack.dropLast().last ?? ""
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
    let geometry: [String: Any]
    if currentGeometryType == "MultiGeometry" {
      guard !multiGeometries.isEmpty else { return }
      geometry = ["type": "GeometryCollection", "geometries": multiGeometries]
    } else if let gType = currentGeometryType, let geom = buildGeometry(type: gType) {
      geometry = geom
    } else {
      return
    }

    var properties: [String: Any] = [:]
    if !currentFeatureName.isEmpty        { properties["name"]        = currentFeatureName }
    if !currentFeatureDescription.isEmpty { properties["description"] = currentFeatureDescription }
    if !currentFeatureStyleUrl.isEmpty {
      properties["styleId"] = currentFeatureStyleUrl
      if let style = resolveStyle(url: currentFeatureStyleUrl), !style.isEmpty {
        properties["style"] = style.asDictionary()
      }
    }

    var feature: [String: Any] = ["type": "Feature", "geometry": geometry, "properties": properties]
    if let id = currentFeatureId, !id.isEmpty { feature["id"] = id }
    features.append(feature)
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
