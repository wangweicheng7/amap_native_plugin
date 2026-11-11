import ArrayList from '@ohos.util.ArrayList';
import { AMap, Circle, CircleOptions, DottedLineType, LatLng, LatLngBounds, Marker, MarkerOptions, Polyline, PolylineOptions } from '@amap/amap_lbs_map3d';
import { Arguments, booleanOf, coordinateOf, mapsOf, numberOf, textOf } from './Protocol';
import { MarkerImage, renderMarker } from './MarkerRenderer';

export class OverlayRenderer {
  private circles: Circle[] = [];
  private lines: Polyline[] = [];
  private markers: Map<number, Marker> = new Map();
  private images: MarkerImage[] = [];
  private generation: number = 0;

  private readonly map: AMap;
  constructor(map: AMap) { this.map = map; }

  updateCircles(values: Arguments[]): void {
    this.circles.forEach((circle: Circle) => circle.remove());
    this.circles = [];
    values.forEach((value: Arguments) => {
      const center = coordinateOf(value.get('center'));
      const radius = numberOf(value.get('radiusMeters'), 0);
      if (center === undefined || radius <= 0) return;
      const options = new CircleOptions().setCenter(center).setRadius(radius)
        .setStrokeWidth(vp2px(numberOf(value.get('strokeWidth'), 2)))
        .setStrokeColor(numberOf(value.get('strokeColor'), 0xFF2563EB))
        .setFillColor(numberOf(value.get('fillColor'), 0x332563EB))
        .setDottedLineType(DottedLineType.DOTTEDLINE_TYPE_SQUARE).setUsePolylineStroke(true);
      const circle = this.map.addCircle(options);
      if (circle !== undefined) this.circles.push(circle);
    });
  }

  updateLines(values: Arguments[]): void {
    this.lines.forEach((line: Polyline) => line.remove());
    this.lines = [];
    values.forEach((value: Arguments) => {
      const points = new ArrayList<LatLng>();
      mapsOf(value.get('points')).forEach((point: Arguments) => {
        const coordinate = coordinateOf(point);
        if (coordinate !== undefined) points.add(coordinate);
      });
      if (points.length < 2) return;
      const options = new PolylineOptions().addAll(points)
        .setColor(numberOf(value.get('color'), 0xFFFF5B00))
        .setWidth(vp2px(numberOf(value.get('width'), 6)))
        .setDottedLine(booleanOf(value.get('dashed')));
      const line = this.map.addPolyline(options);
      if (line !== undefined) this.lines.push(line);
    });
  }

  async updatePins(values: Arguments[]): Promise<void> {
    const generation = ++this.generation;
    this.clearMarkers();
    for (let index = 0; index < values.length; index++) {
      const value = values[index];
      const position = coordinateOf(value.get('position'));
      if (position === undefined) continue;
      const icon = await renderMarker(value);
      if (generation !== this.generation) { icon.release(); return; }
      const marker = this.map.addMarker(new MarkerOptions().setPosition(position)
        .setTitle(textOf(value.get('title'))).setSnippet(textOf(value.get('snippet')))
        .setDraggable(booleanOf(value.get('draggable'))).setAnchor(icon.anchorU, 0.5).setIcon(icon.descriptor));
      if (marker !== undefined) { this.markers.set(index, marker); this.images.push(icon); }
      else icon.release();
    }
  }

  movePins(updates: Arguments[]): void {
    updates.forEach((update: Arguments) => {
      const index = numberOf(update.get('index'), -1);
      const coordinate = coordinateOf(update.get('position'));
      if (coordinate !== undefined) this.markers.get(index)?.setPosition(coordinate);
    });
  }

  dispose(): void {
    ++this.generation;
    this.clearMarkers();
    this.circles.forEach((circle: Circle) => circle.remove());
    this.lines.forEach((line: Polyline) => line.remove());
    this.circles = [];
    this.lines = [];
  }

  private clearMarkers(): void {
    this.markers.forEach((marker: Marker) => marker.remove());
    this.images.forEach((image: MarkerImage) => image.release());
    this.markers.clear();
    this.images = [];
  }
}
