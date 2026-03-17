package expo.modules.geoparser.parsers

import expo.modules.geoparser.GeoParserError
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream

object GeoJSONParser {

    fun parse(input: InputStream, sourceType: String, onFeatures: (List<Map<String, Any?>>, isLast: Boolean) -> Unit): Map<String, Any?> {
        val json = try {
            JSONObject(input.reader(Charsets.UTF_8).readText())
        } catch (e: Exception) {
            throw GeoParserError.ParseError("Invalid JSON")
        }

        val features = extractFeatures(json)
        val batchSize = 200
        if (features.isEmpty()) {
            onFeatures(emptyList(), true)
        } else {
            var idx = 0
            while (idx < features.size) {
                val end = minOf(idx + batchSize, features.size)
                onFeatures(features.subList(idx, end), end >= features.size)
                idx = end
            }
        }

        val result = mutableMapOf<String, Any?>(
            "type" to "FeatureCollection",
            "sourceType" to sourceType
        )
        json.optString("name").takeIf { it.isNotEmpty() }?.let { result["name"] = it }
        json.optJSONObject("properties")?.let { props ->
            props.optString("name").takeIf { it.isNotEmpty() }?.let { result["name"] = it }
            props.optString("description").takeIf { it.isNotEmpty() }?.let { result["description"] = it }
        }

        return result
    }

    private fun extractFeatures(json: JSONObject): List<Map<String, Any?>> {
        return when (val type = json.optString("type")) {
            "FeatureCollection" -> {
                val arr = json.optJSONArray("features") ?: return emptyList()
                (0 until arr.length()).mapNotNull { parseFeature(arr.getJSONObject(it)) }
            }
            "Feature" -> listOfNotNull(parseFeature(json))
            else -> {
                if (isGeometryType(type)) listOfNotNull(bareGeometryToFeature(json))
                else emptyList()
            }
        }
    }

    private fun parseFeature(json: JSONObject): Map<String, Any?>? {
        if (json.optString("type") != "Feature") return null
        val geometry = json.optJSONObject("geometry") ?: return null
        val properties = json.optJSONObject("properties") ?: JSONObject()
        val feature = mutableMapOf<String, Any?>(
            "type" to "Feature",
            "geometry" to toMap(geometry),
            "properties" to toMap(properties)
        )
        json.opt("id")?.takeIf { it != JSONObject.NULL }?.let { feature["id"] = it.toString() }
        return feature
    }

    private fun bareGeometryToFeature(json: JSONObject): Map<String, Any?>? {
        if (json.optString("type").isEmpty()) return null
        return mapOf(
            "type" to "Feature",
            "geometry" to toMap(json),
            "properties" to emptyMap<String, Any?>()
        )
    }

    private fun isGeometryType(type: String): Boolean = type in setOf(
        "Point", "LineString", "Polygon",
        "MultiPoint", "MultiLineString", "MultiPolygon",
        "GeometryCollection"
    )

    fun toMap(obj: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in obj.keys()) map[key] = toKotlin(obj.get(key))
        return map
    }

    private fun toList(arr: JSONArray): List<Any?> =
        (0 until arr.length()).map { toKotlin(arr.get(it)) }

    private fun toKotlin(value: Any?): Any? = when (value) {
        is JSONObject -> toMap(value)
        is JSONArray -> toList(value)
        JSONObject.NULL -> null
        else -> value
    }
}
