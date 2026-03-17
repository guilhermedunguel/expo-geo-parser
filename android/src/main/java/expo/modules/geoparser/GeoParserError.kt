package expo.modules.geoparser

sealed class GeoParserError(message: String) : Exception(message) {
    class InvalidURI(uri: String) : GeoParserError("Invalid URI: $uri")
    object ExtractionFailed       : GeoParserError("Failed to extract archive")
    object NoGeoDataFound         : GeoParserError("No supported geo data found in archive")
    object UnsupportedFormat      : GeoParserError("Unsupported or unrecognised file format")
    class ParseError(msg: String) : GeoParserError("Parse error: $msg")
}
