import NativeModule from "./ExpoGeoParserModule";
import type { GeoJSONFeature, GeoJSONFeatureCollection, ParseFeaturesEvent } from "./ExpoGeoParserModule";

export { default } from "./ExpoGeoParserModule";
export * from "./ExpoGeoParserModule";

export async function parseFile(uri: string): Promise<GeoJSONFeatureCollection> {
  const features: GeoJSONFeature[] = [];

  let resolveDone!: () => void;
  const allReceived = new Promise<void>(r => { resolveDone = r; });

  const sub = NativeModule.addListener(
    "onParseFeatures",
    (e: ParseFeaturesEvent) => {
      for (const f of e.features) features.push(f);
      if (e.isLast) resolveDone();
    }
  );

  try {
    const meta = await NativeModule.parseFile(uri);
    await allReceived;
    return { ...meta, features };
  } finally {
    sub.remove();
  }
}
