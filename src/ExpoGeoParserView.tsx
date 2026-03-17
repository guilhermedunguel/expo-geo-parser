import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoGeoParserViewProps } from './ExpoGeoParser.types';

const NativeView: React.ComponentType<ExpoGeoParserViewProps> =
  requireNativeView('ExpoGeoParser');

export default function ExpoGeoParserView(props: ExpoGeoParserViewProps) {
  return <NativeView {...props} />;
}
