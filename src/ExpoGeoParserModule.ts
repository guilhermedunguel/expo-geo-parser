import { NativeModule, requireNativeModule } from 'expo';

import { ExpoGeoParserEvents } from './ExpoGeoParser.types';

declare class ExpoGeoParserModule extends NativeModule<ExpoGeoParserEvents> {
  hello: () => string;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoGeoParserModule>('ExpoGeoParser');
