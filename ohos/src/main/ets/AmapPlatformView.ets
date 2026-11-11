import { image } from '@kit.ImageKit';
import { AMap, CameraUpdateFactory, LatLng, LatLngBounds, MapView, MapViewComponent, MapViewManager, OnCameraChangeListener } from '@amap/amap_lbs_map3d';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { Arguments, argumentsOf, booleanOf, coordinateArguments, coordinateOf, mapsOf, numberOf } from './Protocol';
import { OverlayRenderer } from './OverlayRenderer';

let mapSequence: number = 0;

@Component
struct AmapComponent {
  @Prop params: Params;
  private customView: AmapPlatformView = this.params.platformView as AmapPlatformView;
  build() {
    MapViewComponent({ mapViewName: this.customView.mapViewName })
      .width('100%').height('100%')
      .onAreaChange((_old: Area, area: Area) => this.customView.setSize(Number(area.width), Number(area.height)))
  }
}
@Builder
function mapBuilder(params: Params) { AmapComponent({ params: params }) }

export class AmapPlatformView extends PlatformView implements MethodCallHandler {
  readonly mapViewName: string;
  private readonly channel: MethodChannel;
  private mapView?: MapView;
  private map?: AMap;
  private overlays?: OverlayRenderer;
  private data: Arguments;
  private disposed: boolean = false;
  private hostActive: boolean;
  private requestedVisible: boolean;
  private resumed: boolean = false;
  private mapLoaded: boolean = false;
  private width: number = 0;
  private height: number = 0;
  private snapshot?: MethodResult;
  private snapshotTimeout?: number;
  private readonly created = (view?: MapView, name?: string): void => {
    if (name !== this.mapViewName || view === undefined || this.disposed) return;
    this.mapView = view;
    view.onCreate();
    view.getMapAsync((map: AMap): void => {
      if (this.disposed) return;
      this.map = map;
      map.setOnMapLoadedListener(() => { if (!this.disposed) this.mapLoaded = true; });
      this.overlays = new OverlayRenderer(map);
      map.getUiSettings()?.setZoomControlsEnabled(false);
      map.setOnCameraChangeListener(new OnCameraChangeListener(
        (position) => { if (!this.disposed) this.channel.invokeMethod('cameraMove', coordinateArguments(position.target)); },
        (position) => { if (!this.disposed) this.channel.invokeMethod('cameraIdle', coordinateArguments(position.target)); }));
      map.setOnMapClickListener((point: LatLng) => { if (!this.disposed) this.channel.invokeMethod('mapTap', coordinateArguments(point)); });
      const center = coordinateOf(this.data.get('initialCenter'));
      if (center !== undefined) map.moveCamera(CameraUpdateFactory.newLatLngZoom(center, numberOf(this.data.get('initialZoom'), 12)));
      this.overlays.updateCircles(mapsOf(this.data.get('circleGeofences')));
      this.overlays.updateLines(mapsOf(this.data.get('polylines')));
      this.overlays.updatePins(mapsOf(this.data.get('pins'))).catch(() => {});
      map.setMyLocationEnabled(booleanOf(this.data.get('showMyLocation')));
      this.syncLifecycle();
    });
  };

  private readonly onDispose: () => void;
  constructor(viewId: number, args: Object, messenger: BinaryMessenger, active: boolean, onDispose: () => void) {
    super();
    this.onDispose = onDispose;
    this.mapViewName = 'amap_native_plugin_' + viewId + '_' + Date.now() + '_' + (++mapSequence);
    this.data = argumentsOf(args);
    this.hostActive = active;
    this.requestedVisible = booleanOf(this.data.get('visible'), true);
    this.channel = new MethodChannel(messenger, 'amap_native_plugin/map_view_' + viewId);
    this.channel.setMethodCallHandler(this);
    MapViewManager.getInstance().registerMapViewCreatedCallback(this.created);
  }

  getView(): WrappedBuilder<[Params]> { return new WrappedBuilder(mapBuilder); }
  setSize(width: number, height: number): void { this.width = width; this.height = height; }
  setHostActive(active: boolean): void { this.hostActive = active; this.syncLifecycle(); }

  onMethodCall(call: MethodCall, result: MethodResult): void { this.handle(call, result); }
  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (this.disposed) { result.error('map_disposed', 'The map has been disposed.', null); return; }
      const args = argumentsOf(call.args);
      switch (call.method) {
        case 'updateMyLocation':
          this.data.set('showMyLocation', booleanOf(args.get('showMyLocation')));
          this.map?.setMyLocationEnabled(booleanOf(args.get('showMyLocation')));
          break;
        case 'setVisible':
          this.requestedVisible = booleanOf(args.get('visible'), true);
          this.syncLifecycle();
          break;
        case 'updateCircleGeofences':
          this.data.set('circleGeofences', mapsOf(args.get('circleGeofences')));
          this.overlays?.updateCircles(mapsOf(args.get('circleGeofences')));
          break;
        case 'updatePolylines':
          this.data.set('polylines', mapsOf(args.get('polylines')));
          this.overlays?.updateLines(mapsOf(args.get('polylines')));
          break;
        case 'updatePins':
          this.data.set('pins', mapsOf(args.get('pins')));
          await this.overlays?.updatePins(mapsOf(args.get('pins')));
          break;
        case 'updateMovingPins':
          const updates = mapsOf(args.get('updates'));
          const pins = mapsOf(this.data.get('pins'));
          updates.forEach((update: Arguments) => {
            const index = numberOf(update.get('index'), -1);
            const position = update.get('position');
            if (index >= 0 && index < pins.length && position !== undefined) pins[index].set('position', position);
          });
          this.overlays?.movePins(updates);
          break;
        case 'moveCamera':
          const center = coordinateOf(args.get('center'));
          if (center === undefined) throw new Error('A valid camera coordinate is required.');
          const zoom = numberOf(args.get('zoom'), 12);
          this.data.set('initialCenter', args.get('center')!);
          this.data.set('initialZoom', zoom);
          this.map?.moveCamera(CameraUpdateFactory.newLatLngZoom(center, zoom));
          break;
        case 'zoomBy':
          if (this.map === undefined) throw new Error('The map is not ready.');
          this.map.moveCamera(CameraUpdateFactory.zoomBy(numberOf(args.get('amount'), 0)));
          break;
        case 'fitAllOverlays':
          this.fit(numberOf(args.get('padding'), 48));
          break;
        case 'takeSnapshot': this.takeSnapshot(result); return;
        case 'dispose': this.dispose(); break;
        default: result.notImplemented(); return;
      }
      result.success(null);
    } catch (cause) { result.error('map_operation_failed', (cause as Error).message, null); }
  }

  private fit(padding: number): void {
    if (this.map === undefined) throw new Error('The map is not ready.');
    const builder = LatLngBounds.builder();
    let count = 0;
    const include = (point?: LatLng): void => { if (point !== undefined) { builder.include(point); ++count; } };
    mapsOf(this.data.get('pins')).forEach((pin: Arguments) => include(coordinateOf(pin.get('position'))));
    mapsOf(this.data.get('polylines')).forEach((line: Arguments) => mapsOf(line.get('points')).forEach((point: Arguments) => include(coordinateOf(point))));
    mapsOf(this.data.get('circleGeofences')).forEach((circle: Arguments) => {
      const center = coordinateOf(circle.get('center'));
      if (center === undefined) return;
      const delta = numberOf(circle.get('radiusMeters'), 0) / 111320;
      const longitude = delta / Math.max(0.01, Math.cos(center.latitude * Math.PI / 180));
      include(new LatLng(Math.max(-85, center.latitude - delta), Math.max(-180, center.longitude - longitude)));
      include(new LatLng(Math.min(85, center.latitude + delta), Math.min(180, center.longitude + longitude)));
    });
    if (count === 0) return;
    const bounds = builder.build();
    if (count > 0 && bounds !== undefined) this.map.moveCamera(CameraUpdateFactory.newLatLngBounds(bounds, vp2px(Math.max(0, padding))));
  }

  private syncLifecycle(): void {
    const resume = this.hostActive && this.requestedVisible && !this.disposed;
    if (!resume) this.finishSnapshot(null, 'map_not_ready', 'The map became hidden or the host became inactive.');
    if (this.mapView === undefined || this.resumed === resume) return;
    this.resumed = resume;
    if (resume) this.mapView.onResume(); else this.mapView.onPause();
  }

  private takeSnapshot(result: MethodResult): void {
    if (this.map === undefined || !this.mapLoaded || !this.resumed || this.width <= 0 || this.height <= 0) {
      result.error('map_not_ready', 'Snapshot requires a visible, foreground map with non-zero size.', null); return;
    }
    if (this.snapshot !== undefined) { result.error('snapshot_in_progress', 'A snapshot is already pending.', null); return; }
    this.snapshot = result;
    this.snapshotTimeout = setTimeout(() => this.finishSnapshot(null), 5000);
    try { this.map.getMapScreenShot({ onMapScreenShot: (bitmap: image.PixelMap | undefined, status: number) => {
      if (this.snapshot !== result) return;
      if (status !== 1) { this.finishSnapshot(null); return; }
      this.encodeSnapshot(bitmap, result);
    } }); }
    catch (cause) { this.finishSnapshot(null, 'snapshot_failed', (cause as Error).message); }
  }

  private async encodeSnapshot(bitmap: image.PixelMap | undefined, pending: MethodResult): Promise<void> {
    if (pending === undefined || bitmap === undefined) { this.finishSnapshot(null); return; }
    const packer = image.createImagePacker();
    try {
      const bytes = await packer.packing(bitmap, { format: 'image/png', quality: 100 });
      if (this.snapshot === pending) this.finishSnapshot(new Uint8Array(bytes));
    } catch (cause) { if (this.snapshot === pending) this.finishSnapshot(null, 'snapshot_failed', (cause as Error).message); }
    finally { await packer.release(); }
  }

  private finishSnapshot(bytes: Uint8Array | null, errorCode?: string, errorMessage?: string): void {
    if (this.snapshotTimeout !== undefined) clearTimeout(this.snapshotTimeout);
    this.snapshotTimeout = undefined;
    const pending = this.snapshot;
    this.snapshot = undefined;
    if (errorCode !== undefined) pending?.error(errorCode, errorMessage ?? errorCode, null);
    else pending?.success(bytes);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.finishSnapshot(null, 'map_disposed', 'The map was disposed during the snapshot request.');
    this.syncLifecycle();
    this.overlays?.dispose();
    this.overlays = undefined;
    MapViewManager.getInstance().unregisterMapViewCreatedCallback(this.created);
    this.mapView?.onDestroy();
    this.mapView = undefined;
    this.map = undefined;
    this.channel.setMethodCallHandler(null);
    this.onDispose();
  }
}
