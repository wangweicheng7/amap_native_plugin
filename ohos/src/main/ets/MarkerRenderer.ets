import { image } from '@kit.ImageKit';
import { BitmapDescriptor, BitmapDescriptorFactory } from '@amap/amap_lbs_map3d';
import { Arguments, numberOf, textOf } from './Protocol';

export class MarkerImage {
  readonly descriptor: BitmapDescriptor;
  readonly bitmap: image.PixelMap;
  readonly anchorU: number;
  constructor(descriptor: BitmapDescriptor, bitmap: image.PixelMap, anchorU: number) {
    this.descriptor = descriptor;
    this.bitmap = bitmap;
    this.anchorU = anchorU;
  }
  release(): void { this.bitmap.release(); }
}

function cssColor(argb: number): string {
  return `rgba(${(argb >>> 16) & 255},${(argb >>> 8) & 255},${argb & 255},${((argb >>> 24) & 255) / 255})`;
}

/** Composes only marker pixels; no host widgets, files, routes or business state. */
export async function renderMarker(args: Arguments): Promise<MarkerImage> {
  const logicalWidth = Math.max(1, Math.min(512, numberOf(args.get('imageWidth'), 24)));
  const logicalHeight = Math.max(1, Math.min(512, numberOf(args.get('imageHeight'), 24)));
  const scale = Math.max(0.5, Math.min(4, numberOf(args.get('labelTextScaleFactor'), 1)));
  const label = textOf(args.get('label')).slice(0, 128);
  const fontSize = 14 * scale;
  const measure = new OffscreenCanvas(1, 1).getContext('2d');
  measure.font = `${fontSize}px sans-serif`;
  const labelWidth = label.length > 0 ? Math.ceil(measure.measureText(label).width) + 16 * scale : 0;
  const gap = labelWidth > 0 ? 6 * scale : 0;
  const width = Math.ceil(logicalWidth + gap + labelWidth);
  const height = Math.ceil(Math.max(logicalHeight, fontSize + 12 * scale));
  const canvas = new OffscreenCanvas(width, height);
  const context = canvas.getContext('2d');
  context.clearRect(0, 0, width, height);
  const bytes = args.get('imageBytes');
  if (bytes instanceof Uint8Array && bytes.byteLength > 0) {
    const source = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
    try {
      const bitmap = await source.createPixelMap();
      try { context.drawImage(bitmap, 0, (height - logicalHeight) / 2, logicalWidth, logicalHeight); }
      finally { await bitmap.release(); }
    } finally { await source.release(); }
  } else {
    context.fillStyle = cssColor(numberOf(args.get('pinColor'), 0xFF9E9E9E));
    context.beginPath();
    context.arc(logicalWidth / 2, height / 2, Math.min(logicalWidth, logicalHeight) / 2, 0, 2 * Math.PI);
    context.fill();
  }
  if (labelWidth > 0) {
    const labelHeight = fontSize + 12 * scale;
    context.fillStyle = cssColor(numberOf(args.get('labelBackgroundColor'), 0xE62D3748));
    context.fillRect(logicalWidth + gap, (height - labelHeight) / 2, labelWidth, labelHeight);
    context.fillStyle = cssColor(numberOf(args.get('labelTextColor'), 0xFFFFFFFF));
    context.font = `${fontSize}px sans-serif`;
    context.textBaseline = 'middle';
    context.fillText(label, logicalWidth + gap + 8 * scale, height / 2);
  }
  const pixelMap = context.getPixelMap(0, 0, width, height);
  const descriptor = BitmapDescriptorFactory.fromPixelMapSync(pixelMap);
  if (descriptor === undefined) {
    await pixelMap.release();
    throw new Error('AMap could not create a marker bitmap.');
  }
  return new MarkerImage(descriptor, pixelMap, logicalWidth / (2 * width));
}
