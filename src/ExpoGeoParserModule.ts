import { NativeModule, requireNativeModule } from "expo";

export type GeoFileType = "kml" | "kmz" | "zip" | "geojson" | "json" | "unknown";

export type DetectedFileType = {
  uri: string;
  fileName?: string | null;
  extension?: string | null;
  type: GeoFileType;
  uti?: string | null;
};

export type GeoJSONGeometry = {
  type: string;
  coordinates?: unknown;
  geometries?: GeoJSONGeometry[];
};

export type GeoJSONFeature = {
  type: "Feature";
  id?: string | number;
  geometry: GeoJSONGeometry;
  properties: Record<string, unknown>;
};

export type GeoJSONFeatureCollection = {
  type: "FeatureCollection";
  name?: string;
  description?: string;
  sourceType?: GeoFileType;
  features: GeoJSONFeature[];
};

export type ParseFeaturesEvent = {
  features: GeoJSONFeature[];
  isLast: boolean;
};

declare class ExpoGeoParserModule extends NativeModule {
  detectFileType(uri: string): DetectedFileType;
  parseFile(uri: string): Promise<Omit<GeoJSONFeatureCollection, "features">>;
  addListener(
    event: "onParseFeatures",
    listener: (event: ParseFeaturesEvent) => void
  ): { remove: () => void };
}

export default requireNativeModule<ExpoGeoParserModule>("ExpoGeoParser");
