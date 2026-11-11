import { LatLng } from '@amap/amap_lbs_map3d';

export type Arguments = Map<string, Object>;

export function argumentsOf(value: Object | null | undefined): Arguments {
  return value instanceof Map ? value as Arguments : new Map<string, Object>();
}

export function numberOf(value: Object | undefined, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

export function booleanOf(value: Object | undefined, fallback: boolean = false): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

export function textOf(value: Object | undefined, fallback: string = ''): string {
  return typeof value === 'string' ? value : fallback;
}

export function mapsOf(value: Object | undefined): Arguments[] {
  if (!Array.isArray(value)) return [];
  return (value as Object[]).map((item: Object): Arguments => argumentsOf(item));
}

export function coordinateOf(value: Object | undefined): LatLng | undefined {
  const args = argumentsOf(value);
  const latitude = numberOf(args.get('latitude'), Number.NaN);
  const longitude = numberOf(args.get('longitude'), Number.NaN);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) {
    return undefined;
  }
  return new LatLng(latitude, longitude);
}

export function coordinateArguments(point: LatLng): Arguments {
  const args = new Map<string, Object>();
  args.set('latitude', point.latitude);
  args.set('longitude', point.longitude);
  return args;
}
