import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import webview from '@ohos.web.webview';
import {
  robotArmClient,
  RobotArmConnectionListener,
  RobotArmConnectionState,
  RobotArmMessageListener
} from '../common/RobotArmClient';

interface OperationPageParams {
  controlUrl?: string;
  host?: string;
  port?: string;
  armConnected?: boolean;
  armIp?: string;
  armPort?: string;
}

interface VisionActionSource {
  option?: string;
  target_x?: number | string;
  target_y?: number | string;
  target_z?: number | string;
  track_id?: number | string;
  class_name?: string;
  click_x_norm?: number | string;
  click_y_norm?: number | string;
  pixel_x?: number | string;
  pixel_y?: number | string;
  timestamp?: number | string;
  source?: string;
}

interface VisionActionPayload {
  option: 'grasp' | 'place';
  targetX: number;
  targetY: number;
  targetZ: number;
  trackId: number;
  className: string;
  clickXNorm: number;
  clickYNorm: number;
  pixelX: number;
  pixelY: number;
  timestamp: number;
  source: string;
}

class VisionBridge {
  constructor(private readonly forwarder: (payload: string) => void) {}

  onVisionAction(payload: string): void {
    this.forwarder(payload);
  }
}

@Entry
@Component
struct OperationPage {
  @State private controlUrl: string = '';
  @State private hostLabel: string = '';
  @State private armConnected: boolean = false;
  @State private isArmConnecting: boolean = false;
  @State private armIp: string = '';
  @State private armPort: string = '';
  @State private armStatusText: string = '机械臂状态：未连接';
  @State private bridgeStatusText: string = '桥接状态：等待网页动作';
  @State private lastActionText: string = '最近动作：暂无';
  @State private lastArmMessage: string = '机械臂消息：暂无';
  @State private armPowered: boolean = false;
  @State private armEnabled: boolean = false;
  @State private armPaused: boolean = false;
  @State private gripperState: boolean = false;
  @State private gripperForcePercent: number = 20;



  private readonly webController: webview.WebviewController = new webview.WebviewController();
  private readonly visionBridge: VisionBridge = new VisionBridge((payload: string): void => {
    this.handleVisionActionJson(payload);
  });
  private readonly armMessageListener: RobotArmMessageListener = (data: string): void => {
    this.lastArmMessage = `机械臂消息：${data || '空消息'}`;
  };
  private readonly armConnectionListener: RobotArmConnectionListener =
    (state: RobotArmConnectionState, detail?: string): void => {
      this.syncArmStatus(state, detail);
    };

  aboutToAppear(): void {
    const params = router.getParams() as OperationPageParams;
    const url = this.normalizeUrl(typeof params?.controlUrl === 'string' ? params.controlUrl : '');
    const host = typeof params?.host === 'string' ? params.host : '';
    const port = typeof params?.port === 'string' ? params.port : '';

    this.controlUrl = url;
    this.hostLabel = host && port ? `${host}:${port}` : url;
    this.armIp = typeof params?.armIp === 'string' ? params.armIp.trim() : '';
    this.armPort = typeof params?.armPort === 'string' ? params.armPort.trim() : '';
    this.armConnected = robotArmClient.isConnected();
    this.syncArmStatus(robotArmClient.getConnectionState(), robotArmClient.getLastError());
    robotArmClient.subscribeMessage(this.armMessageListener);
    robotArmClient.subscribeStatus(this.armConnectionListener);
  }

  aboutToDisappear(): void {
    robotArmClient.unsubscribeMessage(this.armMessageListener);
    robotArmClient.unsubscribeStatus(this.armConnectionListener);
  }

  private normalizeUrl(url: string): string {
    const trimmed = url.trim();
    if (!trimmed) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return `http://${trimmed}`;
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (_err) {
    }
  }

  private syncArmStatus(state: RobotArmConnectionState, detail?: string): void {
    this.armConnected = state === 'connected';
    this.isArmConnecting = state === 'connecting';

    if (state !== 'connected') {
      this.armPowered = false;
      this.armEnabled = false;
      this.armPaused = false;
    }


    if (state === 'connected') {
      this.armStatusText = this.armIp && this.armPort
        ? `机械臂状态：已连接 ${this.armIp}:${this.armPort}`
        : '机械臂状态：已连接';
      return;
    }

    if (state === 'connecting') {
      this.armStatusText = this.armIp && this.armPort
        ? `机械臂状态：连接中 ${this.armIp}:${this.armPort}`
        : '机械臂状态：连接中';
      return;
    }

    if (state === 'error') {
      this.armStatusText = `机械臂状态：连接异常${detail ? ` (${detail})` : ''}`;
      return;
    }

    this.armStatusText = '机械臂状态：未连接';
  }


  private goBack(): void {
    try {
      router.back();
    } catch (_err) {
      this.showToast('返回失败');
    }
  }

  private async toggleArmConnection(): Promise<void> {
    if (this.armConnected) {
      try {
        await robotArmClient.disconnect();
        this.showToast('已断开与机械臂的连接');
      } catch (_err) {
        this.showToast('断开机械臂失败');
      }
      return;
    }

    const ip = this.armIp.trim();
    const port = Number(this.armPort.trim());
    if (!ip || !Number.isInteger(port) || port < 1 || port > 65535) {
      this.showToast('缺少机械臂 IP 或端口，请返回首页检查配置');
      return;
    }

    try {
      await robotArmClient.connect(ip, port);
      this.showToast('成功连接到机械臂');
    } catch (_err) {
      this.showToast('连接机械臂失败，请检查 IP 和端口');
    }
  }

  private async executeRobotTask(task: () => Promise<void>, failureText: string, successText?: string): Promise<boolean> {
    if (!robotArmClient.isConnected()) {
      this.showToast('机械臂未连接');
      return false;
    }

    try {
      await task();
      if (successText) {
        this.showToast(successText);
      }
      return true;
    } catch (_err) {
      this.showToast(failureText);
      return false;
    }
  }

  private async handleTogglePower(): Promise<void> {
    if (this.armPowered) {
      const success = await this.executeRobotTask(() => robotArmClient.powerOff(), '机械臂下电失败', '已发送: poweroff');
      if (success) {
        this.armPowered = false;
        this.armEnabled = false;
      }
      return;
    }

    const success = await this.executeRobotTask(() => robotArmClient.powerOn(), '机械臂上电失败', '已发送: poweron');
    if (success) {
      this.armPowered = true;
      this.armEnabled = false;
    }
  }

  private async handleToggleEnable(): Promise<void> {
    if (!this.armPowered) {
      return;
    }

    if (this.armEnabled) {
      const success = await this.executeRobotTask(() => robotArmClient.disable(), '机械臂下使能失败', '已发送: disable');
      if (success) {
        this.armEnabled = false;
      }
      return;
    }

    const success = await this.executeRobotTask(() => robotArmClient.enable(), '机械臂上使能失败', '已发送: enable');
    if (success) {
      this.armEnabled = true;
    }
  }

  private async handleGripperInit(): Promise<void> {
    void this.executeRobotTask(() => robotArmClient.initGripper(), '夹爪初始化失败', '已发送夹爪初始化');
  }

  private async handleStop(): Promise<void> {
    const success = await this.executeRobotTask(() => robotArmClient.stop(), '机械臂终止失败', '已发送: stop');
    if (success) {
      this.armPaused = false;
    }
  }

  private async handleTogglePauseResume(): Promise<void> {
    const success = this.armPaused
      ? await this.executeRobotTask(() => robotArmClient.resume(), '机械臂继续失败', '已发送: resume')
      : await this.executeRobotTask(() => robotArmClient.pause(), '机械臂暂停失败', '已发送: pause');
    if (success) {
      this.armPaused = !this.armPaused;
    }
  }

  private async handleGripperClose(): Promise<void> {

    const success = await this.executeRobotTask(() => robotArmClient.closeGripper(), '夹爪闭合失败', '已发送夹爪闭合');
    if (success) {
      this.gripperState = true;
    }
  }

  private async handleGripperOpen(): Promise<void> {
    const success = await this.executeRobotTask(() => robotArmClient.openGripper(), '夹爪张开失败', '已发送夹爪张开');
    if (success) {
      this.gripperState = false;
    }
  }

  private async handleSetGripperForce(forcePercent: number): Promise<void> {
    const success = await this.executeRobotTask(
      () => robotArmClient.setGripperForce(forcePercent),
      `夹爪力度设置失败 (${forcePercent}%)`,
      `已发送夹爪力度 ${forcePercent}%`
    );
    if (success) {
      this.gripperForcePercent = forcePercent;
    }
  }

  private handleVisionActionJson(payload: string): void {

    const action = this.parseVisionAction(payload);
    if (!action) {
      this.bridgeStatusText = '桥接状态：收到非法动作数据';
      this.showToast('收到非法动作数据');
      return;
    }

    this.lastActionText = this.describeAction(action);
    void this.dispatchVisionAction(action);
  }

  private parseVisionAction(payload: string): VisionActionPayload | null {
    if (!payload) {
      return null;
    }

    try {
      const source = JSON.parse(payload) as VisionActionSource;
      const option = source.option === 'place' ? 'place' : (source.option === 'grasp' ? 'grasp' : '');
      const targetX = this.toNumber(source.target_x);
      const targetY = this.toNumber(source.target_y);
      const targetZ = this.toNumber(source.target_z);

      if (!option || targetX === null || targetY === null || targetZ === null) {
        return null;
      }

      return {
        option,
        targetX,
        targetY,
        targetZ,
        trackId: this.toNumber(source.track_id) ?? -1,
        className: typeof source.class_name === 'string' ? source.class_name : '',
        clickXNorm: this.toNumber(source.click_x_norm) ?? -1,
        clickYNorm: this.toNumber(source.click_y_norm) ?? -1,
        pixelX: this.toNumber(source.pixel_x) ?? -1,
        pixelY: this.toNumber(source.pixel_y) ?? -1,
        timestamp: this.toNumber(source.timestamp) ?? Date.now(),
        source: typeof source.source === 'string' ? source.source : 'vision_web'
      };
    } catch (_err) {
      return null;
    }
  }

  private toNumber(value: number | string | undefined): number | null {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  }

  private describeAction(action: VisionActionPayload): string {
    if (action.option === 'grasp') {
      const targetLabel = action.trackId >= 0 ? `#${action.trackId}` : '目标';
      const classLabel = action.className ? ` ${action.className}` : '';
      return `最近动作：抓取 ${targetLabel}${classLabel} -> X=${action.targetX}, Y=${action.targetY}, Z=${action.targetZ}`;
    }
    return `最近动作：放置 -> X=${action.targetX}, Y=${action.targetY}, Z=${action.targetZ}`;
  }

  private async dispatchVisionAction(action: VisionActionPayload): Promise<void> {
    this.bridgeStatusText = `桥接状态：已收到网页${action.option === 'grasp' ? '抓取' : '放置'}动作`;

    if (!this.armConnected) {
      this.bridgeStatusText = '桥接状态：已收到动作，但机械臂未连接';
      this.showToast('已收到动作，但机械臂未连接');
      return;
    }

    const success = action.option === 'grasp'
      ? await this.executeRobotTask(
        () => robotArmClient.graspAtPoint(action.targetX, action.targetY, action.targetZ),
        '发送抓取动作失败'
      )
      : await this.executeRobotTask(
        () => robotArmClient.placeAtPoint(action.targetX, action.targetY, action.targetZ),
        '发送放置动作失败'
      );

    if (success) {
      this.gripperState = action.option === 'grasp';
    }
    this.bridgeStatusText = success ? '桥接状态：动作已发送给机械臂' : '桥接状态：动作发送失败';
  }


  build() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 8 }) {
          Text('上位机视觉操作台')
            .width('100%')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111827')

          Text(this.hostLabel || '等待地址信息')
            .width('100%')
            .fontSize(14)
            .fontColor('#6B7280')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6 })

        Row({ space: 12 }) {
          Button('返回首页')
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .backgroundColor('#6B7280')
            .onClick(() => {
              this.goBack();
            })

          Button(this.isArmConnecting ? '连接中...' : (this.armConnected ? '断开机械臂' : '连接机械臂'))
            .layoutWeight(2)
            .height(46)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .backgroundColor(this.isArmConnecting ? '#9CA3AF' : (this.armConnected ? '#EF4444' : '#F59E0B'))
            .enabled(!this.isArmConnecting)
            .onClick(() => {
              this.toggleArmConnection();
            })

          Button('重新加载')
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .backgroundColor('#2563EB')
            .enabled(!!this.controlUrl)
            .onClick(() => {
              if (!this.controlUrl) {
                this.showToast('当前没有可加载的页面地址');
                return;
              }
              this.webController.refresh();
              this.showToast('已请求刷新页面');
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })

        if (this.armConnected) {
          Row({ space: 12 }) {
            Button(this.armPowered ? '机械臂下电' : '机械臂上电')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor(this.armPowered ? '#EF4444' : '#10B981')
              .onClick(() => {
                void this.handleTogglePower();
              })

            Button(this.armEnabled ? '机械臂下使能' : '机械臂上使能')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor(!this.armPowered ? '#9CA3AF' : (this.armEnabled ? '#EF4444' : '#10B981'))
              .enabled(this.armPowered)
              .onClick(() => {
                void this.handleToggleEnable();
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20 })

          Row({ space: 12 }) {
            Button('终止')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor('#EF4444')
              .onClick(() => {
                void this.handleStop();
              })

            Button(this.armPaused ? '继续' : '暂停')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor(this.armPaused ? '#10B981' : '#6B7280')
              .onClick(() => {
                void this.handleTogglePauseResume();
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20 })

          Row({ space: 12 }) {
            Button('夹爪初始化')

              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor('#6B7280')
              .onClick(() => {
                void this.handleGripperInit();
              })

            Button('夹爪闭合')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor('#2563EB')
              .onClick(() => {
                void this.handleGripperClose();
              })

            Button('夹爪张开')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor('#2563EB')
              .onClick(() => {
                void this.handleGripperOpen();
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20 })

          Row({ space: 12 }) {
            Button('力度20%')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor(this.gripperForcePercent === 20 ? '#10B981' : '#6B7280')
              .onClick(() => {
                void this.handleSetGripperForce(20);
              })

            Button('力度60%')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor(this.gripperForcePercent === 60 ? '#10B981' : '#6B7280')
              .onClick(() => {
                void this.handleSetGripperForce(60);
              })

            Button('力度100%')
              .layoutWeight(1)
              .height(46)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .borderRadius(23)
              .backgroundColor(this.gripperForcePercent === 100 ? '#10B981' : '#6B7280')
              .onClick(() => {
                void this.handleSetGripperForce(100);
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20 })
        }

        Column() {

          if (this.controlUrl) {
            Web({ src: this.controlUrl, controller: this.webController })
              .width('100%')
              .height('100%')
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .javaScriptProxy({
                object: this.visionBridge,
                name: 'ohosApp',
                methodList: ['onVisionAction'],
                controller: this.webController
              })
          } else {
            Column({ space: 10 }) {
              Text('请返回首页重新填写上位机地址。')
                .fontSize(13)
                .fontColor('#D1D5DB')
            }
          }
        }
        .width('85%')
        .constraintSize({ minHeight: 300 })
        .height(600)
        .margin({ left: 20, right: 20 })
        .backgroundColor('#111827')
        .borderRadius(18)
        .clip(true)

        Column({ space: 8 }) {
          Text(this.armStatusText)
            .width('100%')
            .fontSize(13)
            .fontColor('#111827')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .backgroundColor('#E5E7EB')
            .borderRadius(12)

          Text(this.bridgeStatusText)
            .width('100%')
            .fontSize(13)
            .fontColor('#111827')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .backgroundColor('#DBEAFE')
            .borderRadius(12)

          Text(this.lastActionText)
            .width('100%')
            .fontSize(13)
            .fontColor('#111827')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .backgroundColor('#FEF3C7')
            .borderRadius(12)

          Text(this.lastArmMessage)
            .width('100%')
            .fontSize(13)
            .fontColor('#111827')
            .padding({ left: 14, right: 14, top: 12, bottom: 12 })
            .backgroundColor('#DCFCE7')
            .borderRadius(12)
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 24 })
      }
      .width('100%')
      .padding({ top: 24 })
      .backgroundColor('#F7F8FA')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

}
