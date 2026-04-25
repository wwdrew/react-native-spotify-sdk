import { Text, View, StyleSheet } from 'react-native';
import { isAvailable } from '@wwdrew/react-native-spotify-sdk';

export default function App() {
  return (
    <View style={styles.container}>
      <Text>Spotify Installed: {isAvailable() ? 'Yes' : 'No'}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
