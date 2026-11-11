import common from '@ohos.app.ability.common';
import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityLifecycleCallback from '@ohos.app.ability.AbilityLifecycleCallback';
import window from '@ohos.window';
import { AMapPrivacyAgreeStatus, AMapPrivacyInfoStatus, AMapPrivacyShowStatus } from '@amap/amap_lbs_common';
import { MapsInitializer } from '@amap/amap_lbs_map3d';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import PlatformView from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import PlatformViewFactory from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformViewFactory';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import { AmapPlatformView } from './AmapPlatformView';

class AmapViewFactory extends PlatformViewFactory {
  initialized: boolean = false;
  private active: boolean = false;
  private readonly views: Map<number, AmapPlatformView> = new Map();
  private readonly messenger: BinaryMessenger;
  constructor(messenger: BinaryMessenger) { super(StandardMessageCodec.INSTANCE); this.messenger = messenger; }
  create(_context: common.Context, id: number, args: Object): PlatformView {
    if (!this.initialized) throw new Error('Call AmapNative.init with an OHOS key and explicit privacy consent before creating a map.');
    const view = new AmapPlatformView(id, args, this.messenger, this.active, () => this.views.delete(id));
    this.views.set(id, view);
    return view;
  }
  setActive(active: boolean): void { this.active = active; this.views.forEach((view: AmapPlatformView) => view.setHostActive(active)); }
  releaseViews(): void { this.views.forEach((view: AmapPlatformView) => view.dispose()); this.views.clear(); }
  dispose(): void { this.releaseViews(); this.initialized = false; }
}

class MapAbilityLifecycle extends AbilityLifecycleCallback {
  private readonly ability: UIAbility;
  private readonly factory: AmapViewFactory;
  private observed: boolean = false;
  initializeVisibility(visible: boolean): void { if (!this.observed) this.factory.setActive(visible); }
  constructor(ability: UIAbility, factory: AmapViewFactory) { super(); this.ability = ability; this.factory = factory; }
  onAbilityCreate(_ability: UIAbility): void {}
  onWindowStageCreate(_ability: UIAbility, _stage: window.WindowStage): void {}
  onWindowStageActive(_ability: UIAbility, _stage: window.WindowStage): void {}
  onWindowStageInactive(_ability: UIAbility, _stage: window.WindowStage): void {}
  onWindowStageDestroy(_ability: UIAbility, _stage: window.WindowStage): void {}
  onAbilityContinue(_ability: UIAbility): void {}
  onAbilityForeground(ability: UIAbility): void { if (ability === this.ability) { this.observed = true; this.factory.setActive(true); } }
  onAbilityBackground(ability: UIAbility): void { if (ability === this.ability) { this.observed = true; this.factory.setActive(false); } }
  onAbilityDestroy(ability: UIAbility): void { if (ability === this.ability) this.factory.dispose(); }
}

export default class AmapNativePlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel?: MethodChannel;
  private context?: common.Context;
  private factory?: AmapViewFactory;
  private application?: common.ApplicationContext;
  private lifecycleId?: number;
  private lifecycle?: MapAbilityLifecycle;

  getUniqueClassName(): string { return 'AmapNativePlugin'; }
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'amap_native_plugin');
    this.channel.setMethodCallHandler(this);
    this.factory = new AmapViewFactory(binding.getBinaryMessenger());
    binding.getPlatformViewRegistry().registerViewFactory('amap_native_plugin/map_view', this.factory);
  }
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.onDetachedFromAbility();
    const factory = this.factory;
    if (factory === undefined) return;
    const ability = binding.getAbility();
    this.application = ability.context.getApplicationContext();
    const lifecycle = new MapAbilityLifecycle(ability, factory);
    this.lifecycle = lifecycle;
    this.lifecycleId = this.application.on('abilityLifecycle', lifecycle);
    // Initial attachment can occur while an existing ability is in the background.
    // A later lifecycle event takes precedence over this asynchronous window query.
    window.getLastWindow(ability.context).then((hostWindow: window.Window) => {
      if (this.lifecycle === lifecycle) lifecycle.initializeVisibility(hostWindow.isWindowShowing());
    }).catch(() => {});
  }
  onDetachedFromAbility(): void {
    if (this.lifecycleId !== undefined) this.application?.off('abilityLifecycle', this.lifecycleId);
    this.lifecycleId = undefined;
    this.lifecycle = undefined;
    this.application = undefined;
    this.factory?.setActive(false);
    this.factory?.releaseViews();
  }
  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.onDetachedFromAbility();
    this.factory?.dispose();
    this.factory = undefined;
    this.channel?.setMethodCallHandler(null);
    this.channel = undefined;
    this.context = undefined;
  }
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'init') { result.notImplemented(); return; }
    const context = this.context;
    const factory = this.factory;
    if (context === undefined || factory === undefined) { result.error('engine_detached', 'The Flutter engine is detached.', null); return; }
    const key = call.argument('ohosApiKey') as string | undefined;
    if (key === undefined || key.trim().length === 0) { result.error('missing_api_key', 'An OHOS AMap SDK key is required.', null); return; }
    if (call.argument('privacyShown') !== true || call.argument('privacyAgreed') !== true) {
      result.error('privacy_not_agreed', 'The host must explicitly confirm the AMap privacy notice and user agreement.', null); return;
    }
    try {
      MapsInitializer.updatePrivacyShow(AMapPrivacyShowStatus.DidShow, AMapPrivacyInfoStatus.DidContain, context);
      MapsInitializer.updatePrivacyAgree(AMapPrivacyAgreeStatus.DidAgree, context);
      MapsInitializer.setApiKey(key.trim());
      MapsInitializer.initialize(context);
      factory.initialized = true;
      result.success(null);
    } catch (cause) { result.error('initialization_failed', (cause as Error).message, null); }
  }
}
