import { useState } from "react";
import { Button, FlatList, StyleSheet, Text, View } from "react-native";
import * as DocumentPicker from "expo-document-picker";
import { parseFile, type GeoJSONFeature, type GeoJSONFeatureCollection } from "expo-geo-parser";

export default function App() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<GeoJSONFeatureCollection | null>(null);
  const [elapsed, setElapsed] = useState<number | null>(null);

  const pickFile = async () => {
    const picked = await DocumentPicker.getDocumentAsync({
      type: "*/*",
      copyToCacheDirectory: true,
    });
    if (picked.canceled) return;

    setLoading(true);
    setError(null);
    setResult(null);
    setElapsed(null);

    const start = Date.now();
    try {
      setResult(await parseFile(picked.assets[0].uri));
    } catch (e: any) {
      setError(e?.message ?? "Unknown error");
    } finally {
      setElapsed(Date.now() - start);
      setLoading(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Geo Parser</Text>
      <Button title="Pick KML / KMZ / ZIP / GeoJSON" onPress={pickFile} />
      {loading && <Text style={styles.loading}>Parsing…</Text>}
      {elapsed != null && !loading && (
        <Text style={styles.elapsed}>Parsed in {(elapsed / 1000).toFixed(2)}s</Text>
      )}
      {error && <Text style={styles.error}>{error}</Text>}

      {result && (
        <FlatList
          style={styles.list}
          data={result.features}
          keyExtractor={(_, i) => String(i)}
          initialNumToRender={20}
          windowSize={10}
          contentContainerStyle={styles.listContent}
          ListHeaderComponent={
            <View style={[styles.card, styles.headerCard]}>
              <Row label="Source" value={result.sourceType} />
              <Row label="Name" value={result.name} />
              <Row label="Features" value={String(result.features.length)} />
              <Row label="Description" value={result.description} />
            </View>
          }
          renderItem={({ item: f, index: i }) => <FeatureCard feature={f} index={i} />}
        />
      )}
    </View>
  );
}

function FeatureCard({ feature: f, index: i }: { feature: GeoJSONFeature; index: number }) {
  const name = f.properties?.name as string | undefined;
  const description = f.properties?.description as string | undefined;

  return (
    <View style={styles.card}>
      <Text style={styles.featureTitle}>{name ?? `Feature ${i + 1}`}</Text>
      <Row label="Geometry" value={f.geometry?.type} />
      <Row label="Description" value={description} />
      <CoordSummary feature={f} />
    </View>
  );
}

function CoordSummary({ feature: f }: { feature: GeoJSONFeature }) {
  const { type, coordinates } = f.geometry ?? {};
  let summary = "";

  if (type === "Point" && Array.isArray(coordinates)) {
    const c = coordinates as number[];
    summary = `${c[0]?.toFixed(6)}, ${c[1]?.toFixed(6)}`;
  } else if (type === "LineString" && Array.isArray(coordinates)) {
    summary = `${(coordinates as number[][]).length} pts`;
  } else if (type === "Polygon" && Array.isArray(coordinates)) {
    const rings = coordinates as number[][][];
    const holes = rings.length - 1;
    summary = `${rings[0]?.length ?? 0} pts${holes > 0 ? `, ${holes} hole${holes > 1 ? "s" : ""}` : ""}`;
  } else if (type?.startsWith("Multi") && Array.isArray(coordinates)) {
    summary = `${(coordinates as unknown[]).length} parts`;
  } else if (type === "GeometryCollection" && Array.isArray(f.geometry?.geometries)) {
    summary = `${f.geometry.geometries.length} geometries`;
  }

  if (!summary) return null;
  return <Text style={styles.coords}>{summary}</Text>;
}

function Row({ label, value }: { label: string; value?: string }) {
  if (!value) return null;
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}:</Text>
      <Text style={styles.value} numberOfLines={2}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, paddingTop: 60, paddingHorizontal: 16, backgroundColor: "#f5f5f5" },
  title: { fontSize: 22, fontWeight: "700", marginBottom: 16, textAlign: "center" },
  loading: { marginTop: 20, textAlign: "center", color: "#555" },
  elapsed: { marginTop: 8, textAlign: "center", fontSize: 13, color: "#007AFF" },
  error: { marginTop: 16, color: "red", textAlign: "center" },
  list: { marginTop: 16, flex: 1 },
  listContent: { paddingBottom: 32, gap: 10 },
  headerCard: { marginBottom: 4 },
  card: {
    backgroundColor: "#fff",
    borderRadius: 10,
    padding: 12,
    shadowColor: "#000",
    shadowOpacity: 0.06,
    shadowRadius: 4,
    shadowOffset: { width: 0, height: 2 },
    elevation: 2,
    gap: 4,
  },
  featureTitle: { fontSize: 15, fontWeight: "600", marginBottom: 4 },
  row: { flexDirection: "row", alignItems: "center", gap: 6 },
  label: { fontSize: 13, fontWeight: "500", color: "#555", minWidth: 80 },
  value: { fontSize: 13, color: "#111", flex: 1 },
  coords: { fontSize: 11, color: "#888", fontFamily: "monospace", marginTop: 2 },
});
