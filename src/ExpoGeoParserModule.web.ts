import { registerWebModule, NativeModule } from 'expo';

import { ExpoGeoParserModuleEvents } from './ExpoGeoParser.types';

class ExpoGeoParserModule extends NativeModule<ExpoGeoParserModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ExpoGeoParserModule, 'ExpoGeoParserModule');
