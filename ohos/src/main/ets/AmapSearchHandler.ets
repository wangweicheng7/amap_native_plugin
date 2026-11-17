import common from '@ohos.app.ability.common';
import {
  AMapException, ServiceSettings, Inputtips, InputtipsQuery, InputtipsListener,
  Tip, LatLonPoint, GeocodeSearch, ReGeocodeQuery, ReGeocodeResult,
  GeocodeResult, OnGeocodeSearchListener
} from '@amap/amap_lbs_search';
import { AMapPrivacyAgreeStatus, AMapPrivacyInfoStatus, AMapPrivacyShowStatus } from '@amap/amap_lbs_common';
import ArrayList from '@ohos.util.ArrayList';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';

class PendingSearch {
  readonly result: MethodResult;
  readonly timer: number;
  readonly owner: Object;
  constructor(result: MethodResult, timer: number, owner: Object) {
    this.result = result;
    this.timer = timer;
    this.owner = owner;
  }
}

export class AmapSearchHandler {
  private initialized: boolean = false;
  private pending: Map<string, PendingSearch> = new Map();

  private readonly context: common.Context;
  constructor(context: common.Context) { this.context = context; }

  initialize(key: string): void {
    this.dispose();
    ServiceSettings.updatePrivacyShow(AMapPrivacyShowStatus.DidShow, AMapPrivacyInfoStatus.DidContain, this.context);
    ServiceSettings.updatePrivacyAgree(AMapPrivacyAgreeStatus.DidAgree, this.context);
    ServiceSettings.getInstance().setApiKey(key);
    this.initialized = true;
  }

  handle(call: MethodCall, result: MethodResult): void {
    const id = call.argument('requestId') as string;
    if (call.method === 'cancelSearch') {
      this.finish(id, null, 'cancelled', 'Search cancelled.');
      result.success(null);
      return;
    }
    if (!this.initialized) {
      result.error('not_initialized', 'Initialize AMap with privacy consent before searching.', null);
      return;
    }
    if (typeof id !== 'string' || id.length === 0 || this.pending.has(id)) {
      result.error('invalid_argument', 'A unique requestId is required.', null);
      return;
    }
    try {
      if (call.method === 'searchPlaces') this.searchPlaces(id, call, result);
      else this.reverseGeocode(id, call, result);
    } catch (cause) {
      const error = cause as Error;
      if (this.pending.has(id)) {
        const code = error instanceof AMapException ? error.getErrorCode() : undefined;
        this.finish(id, null, code === undefined ? 'sdk_error' : this.errorCode(code), error.message, code);
      } else {
        if (error instanceof AMapException) {
          const details = new Map<string, Object>();
          details.set('vendorCode', error.getErrorCode());
          result.error(this.errorCode(error.getErrorCode()), error.getErrorMessage(), details);
        } else result.error('invalid_argument', error.message, null);
      }
    }
  }

  private register(id: string, call: MethodCall, result: MethodResult, owner: Object): void {
    const timeout = call.argument('timeoutMs') as number;
    if (!Number.isFinite(timeout) || timeout < 1 || timeout > 60000) throw new Error('Invalid timeout.');
    const timer = setTimeout(() => this.finish(id, null, 'timeout', 'AMap search timed out.'), timeout);
    this.pending.set(id, new PendingSearch(result, timer, owner));
  }

  private point(value: Map<string, Object> | null | undefined): LatLonPoint | undefined {
    if (value === null || value === undefined) return undefined;
    const latitude = value.get('latitude') as number;
    const longitude = value.get('longitude') as number;
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      Math.abs(latitude) > 90 || Math.abs(longitude) > 180) throw new Error('Invalid GCJ-02 coordinate.');
    return new LatLonPoint(latitude, longitude);
  }

  private searchPlaces(id: string, call: MethodCall, result: MethodResult): void {
    const keyword = call.argument('keyword') as string;
    if (typeof keyword !== 'string' || keyword.trim().length === 0 || keyword.length > 80) throw new Error('Invalid keyword.');
    const city = call.argument('city') as string | undefined;
    const query = new InputtipsQuery(keyword, city);
    query.setCityLimit(call.argument('cityLimit') === true);
    query.setLocation(this.point(call.argument('location') as Map<string, Object> | undefined));
    const listener: InputtipsListener = {
      onGetInputtips: (tips: ArrayList<Tip>, code: number): void => {
        if (code !== 1000) {
          this.finish(id, null, this.errorCode(code), 'AMap input tips failed.', code);
          return;
        }
        const values: Map<string, Object | null>[] = [];
        tips.forEach((tip: Tip) => {
          const point = tip.getPoint();
          const value = new Map<string, Object | null>();
          value.set('id', tip.getPoiID() ?? '');
          value.set('name', tip.getName() ?? '');
          value.set('address', tip.getAddress() ?? '');
          value.set('district', tip.getDistrict() ?? '');
          value.set('adCode', tip.getAdcode() ?? '');
          value.set('latitude', point?.getLatitude() ?? null);
          value.set('longitude', point?.getLongitude() ?? null);
          values.push(value);
        });
        this.finish(id, values);
      }
    };
    const search = new Inputtips(this.context, listener, query);
    this.register(id, call, result, search);
    search.requestInputtipsAsyn();
  }

  private reverseGeocode(id: string, call: MethodCall, result: MethodResult): void {
    const point = this.point(call.argument('position') as Map<string, Object>);
    const radius = call.argument('radiusMeters') as number;
    if (point === undefined || !Number.isFinite(radius) || radius < 1 || radius > 3000) throw new Error('Invalid reverse geocoding arguments.');
    const search = new GeocodeSearch(this.context);
    const listener: OnGeocodeSearchListener = {
      onGeocodeSearched: (_value: GeocodeResult | undefined, _code: number): void => {},
      onReGeocodeSearched: (value: ReGeocodeResult | undefined, code: number): void => {
        if (code !== 1000) {
          this.finish(id, null, this.errorCode(code), 'AMap reverse geocoding failed.', code);
          return;
        }
        const address = value?.getReGeocodeAddress();
        if (address === undefined) { this.finish(id, null); return; }
        const fields = new Map<string, Object>();
        fields.set('formattedAddress', address.getFormatAddress() ?? '');
        fields.set('province', address.getProvince() ?? '');
        fields.set('city', address.getCity() ?? '');
        fields.set('district', address.getDistrict() ?? '');
        fields.set('adCode', address.getAdCode() ?? '');
        const hasAddress = Array.from(fields.values()).some((item: Object) => (item as string).trim().length > 0);
        this.finish(id, hasAddress ? fields : null);
      }
    };
    search.setOnGeocodeSearchListener(listener);
    this.register(id, call, result, search);
    search.getFromLocationAsyn(new ReGeocodeQuery(point, radius, GeocodeSearch.AMAP));
  }

  private errorCode(code: number): string {
    if (code === 1004 || code === 1005 || code === 1010) return 'rate_limited';
    if (code >= 1001 && code <= 1014) return 'auth_error';
    if (code === 1102 || code === 1103 || code === 1802) return 'timeout';
    if (code === 1804 || code === 1805 || code === 1806) return 'network_error';
    if (code === 1200 || code === 1201 || code === 1202 || code === 1813) return 'invalid_argument';
    if (code === 1807) return 'cancelled';
    return 'sdk_error';
  }

  private finish(id: string, value: Object | null, error?: string, message?: string, vendorCode?: number): void {
    const request = this.pending.get(id);
    if (request === undefined) return;
    this.pending.delete(id);
    clearTimeout(request.timer);
    if (error === undefined) request.result.success(value);
    else {
      const details = new Map<string, Object>();
      if (vendorCode !== undefined) details.set('vendorCode', vendorCode);
      request.result.error(error, message ?? '', details);
    }
  }

  dispose(): void {
    this.initialized = false;
    Array.from(this.pending.keys()).forEach((id: string) => this.finish(id, null, 'cancelled', 'Search service detached or reinitialized.'));
  }
}
