package expo.modules.geoparser.parsers

import expo.modules.geoparser.GeoParserError
import org.xml.sax.Attributes
import org.xml.sax.helpers.DefaultHandler
import java.io.InputStream
import javax.xml.parsers.SAXParserFactory

class KMLParser(
    private val batchSize: Int = 200,
    private val onFeatures: (List<Map<String, Any?>>, isLast: Boolean) -> Unit
) : DefaultHandler() {

    private val featureBuffer = mutableListOf<Map<String, Any?>>()
    var documentName = ""
    var documentDescription = ""
    private val styles = mutableMapOf<String, StyleInfo>()
    private val styleMaps = mutableMapOf<String, String>()

    private val elementStack = mutableListOf<String>()
    private val textBuffer = StringBuilder()

    private var documentDepth = 0
    private var documentMetaCaptured = false

    private var inPlacemark = false
    private var currentFeatureId: String? = null
    private var currentFeatureName = ""
    private var currentFeatureDescription = ""
    private var currentFeatureStyleUrl = ""
    private var currentExtendedData = linkedMapOf<String, Any?>()
    private var currentExtendedDataName = ""
    private var inExtendedData = false
    private var currentGeometryType: String? = null

    private var pointCoord = listOf<Double>()
    private var lineCoords = listOf<List<Double>>()
    private var currentRing = listOf<List<Double>>()
    private var outerRing = listOf<List<Double>>()
    private var innerRings = mutableListOf<List<List<Double>>>()
    private var inOuterBoundary = false
    private var inInnerBoundary = false

    private var inMultiGeometry = false
    private var multiGeometries = mutableListOf<Map<String, Any?>>()

    private var currentStyleId: String? = null
    private var buildingStyle = StyleInfo()
    private var inLineStyle = false
    private var inPolyStyle = false
    private var inIconStyle = false
    private var inIconHref = false

    private var inStyleMap = false
    private var currentStyleMapId: String? = null
    private var inPair = false
    private var currentPairKey = ""
    private var currentPairStyleUrl = ""

    companion object {
        fun parse(input: InputStream, sourceType: String, onFeatures: (List<Map<String, Any?>>, Boolean) -> Unit): Map<String, Any?> {
            val handler = KMLParser(onFeatures = onFeatures)
            val factory = SAXParserFactory.newInstance().apply { isNamespaceAware = true }
            try {
                factory.newSAXParser().parse(input, handler)
            } catch (e: Exception) {
                throw GeoParserError.ParseError(e.message ?: "XML parse error")
            }
            val result = mutableMapOf<String, Any?>(
                "type" to "FeatureCollection",
                "sourceType" to sourceType
            )
            if (handler.documentName.isNotEmpty()) result["name"] = handler.documentName
            if (handler.documentDescription.isNotEmpty()) result["description"] = handler.documentDescription
            return result
        }
    }

    override fun startElement(uri: String?, localName: String?, qName: String?, attrs: Attributes?) {
        val name = stripped(localName ?: qName ?: "")
        elementStack.add(name)
        textBuffer.clear()

        when (name) {
            "Document"       -> documentDepth++
            "Style"          -> { currentStyleId = attrs?.getValue("id"); buildingStyle = StyleInfo() }
            "StyleMap"       -> { inStyleMap = true; currentStyleMapId = attrs?.getValue("id") }
            "Pair"           -> if (inStyleMap) { inPair = true; currentPairKey = ""; currentPairStyleUrl = "" }
            "LineStyle"      -> inLineStyle = true
            "PolyStyle"      -> inPolyStyle = true
            "IconStyle"      -> inIconStyle = true
            "Icon"           -> if (inIconStyle) inIconHref = true
            "Placemark"      -> {
                inPlacemark = true
                currentFeatureId = attrs?.getValue("id")
                currentFeatureName = ""
                currentFeatureDescription = ""
                currentFeatureStyleUrl = ""
                currentExtendedData = linkedMapOf()
                currentExtendedDataName = ""
                inExtendedData = false
                currentGeometryType = null
                multiGeometries = mutableListOf()
            }
            "ExtendedData"   -> if (inPlacemark) inExtendedData = true
            "Data", "SimpleData" -> if (inPlacemark && inExtendedData) currentExtendedDataName = attrs?.getValue("name") ?: ""
            "Point"          -> { currentGeometryType = "Point";      pointCoord = listOf() }
            "LineString"     -> { currentGeometryType = "LineString"; lineCoords = listOf() }
            "LinearRing"     -> currentRing = listOf()
            "Polygon"        -> {
                currentGeometryType = "Polygon"
                outerRing = listOf(); innerRings = mutableListOf()
                inOuterBoundary = false; inInnerBoundary = false
            }
            "MultiGeometry"  -> { inMultiGeometry = true; multiGeometries = mutableListOf() }
            "outerBoundaryIs" -> { inOuterBoundary = true;  inInnerBoundary = false }
            "innerBoundaryIs" -> { inInnerBoundary = true; inOuterBoundary = false }
        }
    }

    override fun characters(ch: CharArray?, start: Int, length: Int) {
        if (ch != null) textBuffer.append(ch, start, length)
    }

    override fun endElement(uri: String?, localName: String?, qName: String?) {
        val name = stripped(localName ?: qName ?: "")
        val text = textBuffer.toString().trim()
        val parent = elementStack.dropLast(1).lastOrNull() ?: ""
        textBuffer.clear()
        if (elementStack.isNotEmpty()) elementStack.removeAt(elementStack.lastIndex)

        when (name) {
            "Document"   -> documentDepth--
            "name"       -> when {
                inPlacemark && parent == "Placemark" -> currentFeatureName = text
                isCollectionContainer(parent) && !documentMetaCaptured -> {
                    documentName = text
                    documentMetaCaptured = true
                }
            }
            "description" -> when {
                inPlacemark && parent == "Placemark" -> currentFeatureDescription = text
                isCollectionContainer(parent) && documentDescription.isEmpty() -> documentDescription = text
            }
            "ExtendedData" -> inExtendedData = false
            "Data" -> currentExtendedDataName = ""
            "value" -> if (inPlacemark && inExtendedData && currentExtendedDataName.isNotEmpty()) {
                currentExtendedData[currentExtendedDataName] = parsePropertyValue(text)
            }
            "SimpleData" -> {
                if (inPlacemark && inExtendedData && currentExtendedDataName.isNotEmpty()) {
                    currentExtendedData[currentExtendedDataName] = parsePropertyValue(text)
                }
                currentExtendedDataName = ""
            }
            "Style"      -> { currentStyleId?.let { styles[it] = buildingStyle }; currentStyleId = null }
            "StyleMap"   -> { inStyleMap = false; currentStyleMapId = null }
            "Pair"       -> {
                if (inStyleMap && currentPairKey == "normal") currentStyleMapId?.let { styleMaps[it] = currentPairStyleUrl }
                inPair = false
            }
            "key"        -> if (inStyleMap && inPair) currentPairKey = text
            "styleUrl"   -> when {
                inPlacemark -> currentFeatureStyleUrl = text
                inStyleMap && inPair -> currentPairStyleUrl = text
            }
            "LineStyle"  -> inLineStyle = false
            "PolyStyle"  -> inPolyStyle = false
            "IconStyle"  -> inIconStyle = false
            "Icon"       -> inIconHref = false
            "color"      -> {
                val hex = kmlColorToCSS(text)
                when {
                    inLineStyle -> buildingStyle.strokeColor = hex
                    inPolyStyle -> buildingStyle.fillColor = hex
                }
            }
            "width"      -> if (inLineStyle) text.toDoubleOrNull()?.let { buildingStyle.strokeWidth = it }
            "fill"       -> if (inPolyStyle) buildingStyle.fillEnabled = text != "0"
            "href"       -> if (inIconHref) buildingStyle.iconUrl = text
            "scale"      -> if (inIconStyle) text.toDoubleOrNull()?.let { buildingStyle.iconScale = it }
            "coordinates" -> {
                val coords = parseCoordinates(text)
                when (parent) {
                    "Point"      -> pointCoord = coords.firstOrNull() ?: listOf()
                    "LineString" -> lineCoords = coords
                    "LinearRing" -> currentRing = coords
                }
            }
            "LinearRing"      -> when {
                inOuterBoundary -> outerRing = currentRing
                inInnerBoundary -> innerRings.add(currentRing)
            }
            "outerBoundaryIs" -> inOuterBoundary = false
            "innerBoundaryIs" -> inInnerBoundary = false
            "Point", "LineString", "Polygon" -> {
                if (inMultiGeometry) {
                    buildGeometry(name)?.let {
                        multiGeometries.add(it)
                        pointCoord = listOf(); lineCoords = listOf()
                        outerRing = listOf(); innerRings = mutableListOf()
                    }
                }
            }
            "MultiGeometry" -> { inMultiGeometry = false; currentGeometryType = "MultiGeometry" }
            "Placemark"     -> { finalizeFeature(); inPlacemark = false }
        }
    }

    override fun endDocument() {
        onFeatures(featureBuffer.toList(), true)
        featureBuffer.clear()
    }

    private fun stripped(name: String): String {
        val idx = name.lastIndexOf(':')
        return if (idx >= 0) name.substring(idx + 1) else name
    }

    private fun isCollectionContainer(name: String): Boolean =
        name == "Document" || name == "Folder"

    private fun kmlColorToCSS(kml: String): String {
        val s = kml.trim().lowercase()
        if (s.length != 8) return "#000000"
        return "#${s.substring(6, 8)}${s.substring(4, 6)}${s.substring(2, 4)}"
    }

    private fun parseCoordinates(text: String): List<List<Double>> =
        text.trim().split(Regex("\\s+"))
            .filter { it.isNotEmpty() }
            .mapNotNull { tuple ->
                val parts = tuple.split(",").mapNotNull { it.toDoubleOrNull() }
                if (parts.size >= 2) parts else null
            }

    private fun parsePropertyValue(text: String): Any {
        val trimmed = text.trim()
        return when {
            trimmed.equals("true", ignoreCase = true) -> true
            trimmed.equals("false", ignoreCase = true) -> false
            NUMERIC_SCALAR.matches(trimmed) -> trimmed.toDouble()
            else -> trimmed
        }
    }

    private fun buildGeometry(type: String): Map<String, Any?>? = when (type) {
        "Point"      -> if (pointCoord.isNotEmpty()) mapOf("type" to "Point", "coordinates" to pointCoord) else null
        "LineString" -> if (lineCoords.isNotEmpty()) mapOf("type" to "LineString", "coordinates" to lineCoords) else null
        "Polygon"    -> if (outerRing.isNotEmpty()) mapOf("type" to "Polygon", "coordinates" to (listOf(outerRing) + innerRings)) else null
        else         -> null
    }

    private fun resolveStyle(url: String): StyleInfo? {
        val id = if (url.startsWith("#")) url.drop(1) else url
        styles[id]?.let { return it }
        styleMaps[id]?.let { normalUrl ->
            val nid = if (normalUrl.startsWith("#")) normalUrl.drop(1) else normalUrl
            return styles[nid]
        }
        return null
    }

    private fun finalizeFeature() {
        val properties = mutableMapOf<String, Any?>()
        if (currentFeatureName.isNotEmpty()) properties["name"] = currentFeatureName
        properties.putAll(currentExtendedData)
        if (currentFeatureDescription.isNotEmpty()) {
            val extracted = extractDescriptionAttributes(currentFeatureDescription)
            extracted.attributes.forEach { (key, value) -> properties.putIfAbsent(key, value) }
            extracted.description?.let { properties["description"] = it }
        }
        if (currentFeatureStyleUrl.isNotEmpty()) {
            properties["styleId"] = currentFeatureStyleUrl
            resolveStyle(currentFeatureStyleUrl)?.takeIf { !it.isEmpty }?.let {
                properties["style"] = it.asDictionary()
            }
        }

        val geometries: List<Map<String, Any?>> = if (currentGeometryType == "MultiGeometry") {
            if (multiGeometries.isEmpty()) return
            multiGeometries.toList()
        } else {
            val gType = currentGeometryType ?: return
            listOf(buildGeometry(gType) ?: return)
        }

        geometries.forEachIndexed { index, geometry ->
            val feature = mutableMapOf<String, Any?>(
                "type" to "Feature",
                "geometry" to geometry,
                "properties" to properties
            )
            splitFeatureId(currentFeatureId, index, geometries.size)?.let { feature["id"] = it }

            featureBuffer.add(feature)
            if (featureBuffer.size >= batchSize) {
                onFeatures(featureBuffer.toList(), false)
                featureBuffer.clear()
            }
        }
    }

    private fun splitFeatureId(baseId: String?, index: Int, total: Int): String? {
        if (baseId.isNullOrEmpty()) return null
        if (total <= 1) return baseId
        return "${baseId}_${index + 1}"
    }

    private fun extractDescriptionAttributes(description: String): ExtractedDescription {
        val textDescription = stripHtml(description)
        if (!description.contains("<table") || !description.contains("<th") || !description.contains("<td")) {
            return ExtractedDescription(linkedMapOf(), textDescription.ifEmpty { null })
        }

        val attributes = linkedMapOf<String, Any?>()
        for (match in HTML_ATTRIBUTE_ROW.findAll(description)) {
            val key = stripHtml(match.groupValues[1])
            if (key.isEmpty()) continue
            val value = stripHtml(match.groupValues[2])
            attributes[key] = parsePropertyValue(value)
        }

        val cleanedDescription =
            if (textDescription.isNotEmpty() && !(attributes.isNotEmpty() && textDescription == "Attributes")) {
                textDescription
            } else {
                null
            }

        return ExtractedDescription(attributes, cleanedDescription)
    }

    private fun stripHtml(value: String): String =
        value
            .replace(HTML_TAG, " ")
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace(WHITESPACE, " ")
            .trim()

    private data class ExtractedDescription(
        val attributes: LinkedHashMap<String, Any?>,
        val description: String?
    )
}

private data class StyleInfo(
    var strokeColor: String? = null,
    var strokeWidth: Double? = null,
    var fillColor: String? = null,
    var fillEnabled: Boolean = true,
    var iconUrl: String? = null,
    var iconScale: Double? = null
) {
    val isEmpty: Boolean get() = strokeColor == null && fillColor == null && iconUrl == null

    fun asDictionary(): Map<String, Any?> {
        val d = mutableMapOf<String, Any?>()
        strokeColor?.let { d["strokeColor"] = it }
        strokeWidth?.let { d["strokeWidth"] = it }
        fillColor?.let { d["fillColor"] = it }
        if (!fillEnabled) d["fillEnabled"] = false
        iconUrl?.let { d["iconUrl"] = it }
        iconScale?.let { d["iconScale"] = it }
        return d
    }
}

private val HTML_TAG = Regex("<[^>]+>")
private val HTML_ATTRIBUTE_ROW = Regex(
    "<th[^>]*>\\s*(.*?)\\s*</th>\\s*<td[^>]*>\\s*(.*?)\\s*</td>",
    setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
)
private val WHITESPACE = Regex("\\s+")
private val NUMERIC_SCALAR = Regex("^-?(0|[1-9]\\d*)(\\.\\d+)?$")
