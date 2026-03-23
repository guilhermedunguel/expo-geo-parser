import { NativeModule, requireNativeModule } from "expo";
import type { File, FeatureCollection, ParseFeaturesEvent } from "./ExpoGeoParser.types";

export type { GeoFileType, File, Feature, Geometry, FeatureCollection, ParseFeaturesEvent } from "./ExpoGeoParser.types";

declare class ExpoGeoParserModule extends NativeModule {
  detectFileType(uri: string): File;
  parseFile(uri: string): Promise<Omit<FeatureCollection, "features">>;
  addListener(
    event: "onParseFeatures",
    listener: (event: ParseFeaturesEvent) => void
  ): { remove: () => void };
}

export default requireNativeModule<ExpoGeoParserModule>("ExpoGeoParser");
