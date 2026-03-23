import NativeModule from "./ExpoGeoParserModule";
import type { Feature, FeatureCollection, ParseFeaturesEvent } from "./ExpoGeoParserModule";
export { default } from "./ExpoGeoParserModule";
export * from "./ExpoGeoParserModule";

export async function parseFile(uri: string): Promise<FeatureCollection> {
  const features: Feature[] = [];

  let resolveDone!: () => void;
  const allReceived = new Promise<void>(received => { resolveDone = received; });

  const subscription = NativeModule.addListener(
    "onParseFeatures",
    (event: ParseFeaturesEvent) => {
      for (const feature of event.features) features.push(feature);
      if (event.isLast) resolveDone();
    }
  );

  try {
    const result = await NativeModule.parseFile(uri);
    await allReceived;

    return { ...result, features };
  } finally {
    subscription.remove();
  }
}
