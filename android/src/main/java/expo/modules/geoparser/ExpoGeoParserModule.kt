package expo.modules.geoparser

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.net.URL

class ExpoGeoParserModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoGeoParser")

    Function("hello") {
      "Hello from Android"
    }
  }
}