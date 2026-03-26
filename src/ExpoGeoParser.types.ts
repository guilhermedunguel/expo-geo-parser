export type GeoFileType = "kml" | "kmz" | "zip" | "geojson" | "json" | "unknown";

export type File = {
  uri: string;
  fileName?: string | null;
  extension?: string | null;
  type: GeoFileType;
  uti?: string | null;
};

// GeoJSON-compliant geometry types (RFC 7946)

export type Position = number[]; // [longitude, latitude, ?altitude]

export type Point = {
  type: "Point";
  coordinates: Position;
};

export type LineString = {
  type: "LineString";
  coordinates: Position[];
};

export type Polygon = {
  type: "Polygon";
  coordinates: Position[][];
};

export type MultiPoint = {
  type: "MultiPoint";
  coordinates: Position[];
};

export type MultiLineString = {
  type: "MultiLineString";
  coordinates: Position[][];
};

export type MultiPolygon = {
  type: "MultiPolygon";
  coordinates: Position[][][];
};

export type GeometryCollection = {
  type: "GeometryCollection";
  geometries: Geometry[];
};

export type Geometry =
  | Point
  | LineString
  | Polygon
  | MultiPoint
  | MultiLineString
  | MultiPolygon
  | GeometryCollection;

export type Feature = {
  type: "Feature";
  id?: string;
  geometry: Geometry;
  properties: Record<string, unknown>;
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
