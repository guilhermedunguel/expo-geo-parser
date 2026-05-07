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

export type Position = [number, number, ...number[]];

export type PointGeometry = {
  type: "Point";
  coordinates: Position;
};

export type MultiPointGeometry = {
  type: "MultiPoint";
  coordinates: Position[];
};

export type LineStringGeometry = {
  type: "LineString";
  coordinates: Position[];
};

export type MultiLineStringGeometry = {
  type: "MultiLineString";
  coordinates: Position[][];
};

export type PolygonGeometry = {
  type: "Polygon";
  coordinates: Position[][];
};

export type MultiPolygonGeometry = {
  type: "MultiPolygon";
  coordinates: Position[][][];
};

export type GeometryCollectionGeometry = {
  type: "GeometryCollection";
  geometries: Geometry[];
};

export type Geometry =
  | PointGeometry
  | MultiPointGeometry
  | LineStringGeometry
  | MultiLineStringGeometry
  | PolygonGeometry
  | MultiPolygonGeometry
  | GeometryCollectionGeometry;

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
