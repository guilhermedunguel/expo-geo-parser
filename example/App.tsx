import {hello} from 'expo-geo-parser';
import { Text, View } from 'react-native';

export default function App() {
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <Text>{hello()}</Text>
    </View>
  );
}
