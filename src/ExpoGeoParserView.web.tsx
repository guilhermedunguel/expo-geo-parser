import * as React from 'react';

import { ExpoGeoParserViewProps } from './ExpoGeoParser.types';

export default function ExpoGeoParserView(props: ExpoGeoParserViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
