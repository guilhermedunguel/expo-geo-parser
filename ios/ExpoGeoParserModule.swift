import ExpoModulesCore

public class ExpoGeoParserModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoGeoParser")

    Function("hello") {
      return "Hello from iOS"
    }
  }
}