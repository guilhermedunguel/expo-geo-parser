export type GeoFileType = "kml" | "kmz" | "zip" | "geojson" | "json" | "unknown";

export type File = {
  uri: string;
  fileName?: string | null;
  extension?: string | null;
  type: GeoFileType;
  uti?: string | null;
};

export type Feature = {
  type: "Feature";
  id?: string | number;
  geometry: Geometry;
  properties: Record<string, unknown>;
};

export type Geometry = {
  type: string;
  coordinates?: number[][];
  geometries?: Geometry[];
};

export type FeatureCollection = {
  type: "FeatureCollection";
  name?: string;
  description?: string;
  sourceType?: GeoFileType;
  features: Feature[];
};

export type ParseFeaturesEvent = {
  features: Feature[];
  isLast: boolean;
};
