package expo.modules.geoparser

import android.net.Uri
import expo.modules.geoparser.parsers.GeoJSONParser
import expo.modules.geoparser.parsers.KMLParser
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.util.zip.ZipInputStream

class ExpoGeoParserModule : Module() {
    override fun definition() = ModuleDefinition {
        Name("ExpoGeoParser")
        Events("onParseFeatures")

        Function("detectFileType") { uri: String ->
            detectFileType(uri)
        }

        AsyncFunction("parseFile") { uri: String ->
            parseGeoFile(uri) { batch, isLast ->
                sendEvent("onParseFeatures", mapOf(
                    "features" to batch,
                    "isLast" to isLast
                ))
            }
        }
    }

    private fun detectFileType(uri: String): Map<String, Any?> {
        val parsed = Uri.parse(uri)
        val fileName = parsed.lastPathSegment
        val ext = fileName?.substringAfterLast('.', "")?.lowercase()?.takeIf { it.isNotEmpty() }
        val type = when (ext) {
            "kml"     -> "kml"
            "kmz"     -> "kmz"
            "zip"     -> "zip"
            "geojson" -> "geojson"
            "json"    -> "json"
            else      -> "unknown"
        }
        return mapOf("uri" to uri, "fileName" to fileName, "extension" to ext, "type" to type, "uti" to null)
    }

    private fun openStream(uri: String): InputStream {
        val parsed = Uri.parse(uri)
        if (parsed.scheme == "file") {
            return File(parsed.path ?: throw GeoParserError.InvalidURI(uri)).inputStream()
        }
        val context = appContext.reactContext ?: throw GeoParserError.InvalidURI(uri)
        return context.contentResolver.openInputStream(parsed) ?: throw GeoParserError.InvalidURI(uri)
    }

    private fun parseGeoFile(uri: String, onFeatures: (List<Map<String, Any?>>, Boolean) -> Unit): Map<String, Any?> {
        val parsed = Uri.parse(uri)
        val ext = parsed.lastPathSegment?.substringAfterLast('.', "")?.lowercase() ?: ""

        if (ext == "kmz" || ext == "zip") return parseArchive(uri, ext, onFeatures)

        return openStream(uri).use { stream ->
            when (ext) {
                "kml"             -> KMLParser.parse(stream, "kml", onFeatures)
                "geojson", "json" -> GeoJSONParser.parse(stream, ext, onFeatures)
                else              -> sniffAndParse(stream, "unknown", onFeatures)
            }
        }
    }

    private fun parseArchive(uri: String, sourceType: String, onFeatures: (List<Map<String, Any?>>, Boolean) -> Unit): Map<String, Any?> {
        val context = appContext.reactContext ?: throw GeoParserError.InvalidURI(uri)
        val tmpDir = File(context.cacheDir, UUID.randomUUID().toString()).also { it.mkdirs() }
        try {
            var bestKmlFile: File? = null
            var firstGeoJsonFile: File? = null

            openStream(uri).use { raw ->
                ZipInputStream(raw).use { zip ->
                    var entry = zip.nextEntry
                    while (entry != null) {
                        val entryExt = entry.name.substringAfterLast('.', "").lowercase()
                        if (!entry.isDirectory) {
                            when (entryExt) {
                                "kml" -> {
                                    val outFile = File(tmpDir, entry.name.substringAfterLast('/'))
                                    outFile.parentFile?.mkdirs()
                                    outFile.outputStream().use { zip.copyTo(it) }
                                    if (bestKmlFile == null || entry.name.lowercase().endsWith("doc.kml")) {
                                        bestKmlFile = outFile
                                    }
                                }
                                "geojson", "json" -> {
                                    if (firstGeoJsonFile == null) {
                                        val outFile = File(tmpDir, entry.name.substringAfterLast('/'))
                                        outFile.outputStream().use { zip.copyTo(it) }
                                        firstGeoJsonFile = outFile
                                    }
                                }
                            }
                        }
                        zip.closeEntry()
                        entry = zip.nextEntry
                    }
                }
            }

            bestKmlFile?.let { file ->
                return file.inputStream().use { KMLParser.parse(it, sourceType, onFeatures) }
            }
            firstGeoJsonFile?.let { file ->
                return file.inputStream().use { GeoJSONParser.parse(it, sourceType, onFeatures) }
            }

            throw GeoParserError.NoGeoDataFound
        } finally {
            tmpDir.deleteRecursively()
        }
    }

    private fun sniffAndParse(stream: InputStream, sourceType: String, onFeatures: (List<Map<String, Any?>>, Boolean) -> Unit): Map<String, Any?> {
        val buffered = stream.buffered()
        buffered.mark(512)
        val peek = ByteArray(256)
        val n = buffered.read(peek)
        buffered.reset()
        val prefix = if (n > 0) String(peek, 0, n, Charsets.UTF_8) else ""
        return when {
            prefix.trimStart().startsWith("{")                                               -> GeoJSONParser.parse(buffered, sourceType, onFeatures)
            "<kml" in prefix || "<Placemark" in prefix || "<Document" in prefix -> KMLParser.parse(buffered, sourceType, onFeatures)
            else -> throw GeoParserError.UnsupportedFormat
        }
    }
}
