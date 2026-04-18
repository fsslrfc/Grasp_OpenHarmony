import connection from '@ohos.net.connection';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import { robotArmClient } from '../common/RobotArmClient';

interface LinkAddressCompat {
  address?: {
    address?: string;
  };
}

interface ConnectionPropertiesCompat {
  linkAddresses?: LinkAddressCompat[];
}

interface ConnectionApiCompat {
  getDefaultNetSync?: () => unknown;
  getConnectionPropertiesSync?: (netHandle: unknown) => ConnectionPropertiesCompat;
  getDefaultNet?: (callback: (err: unknown, netHandle: unknown) => void) => void;
  getConnectionProperties?: (netHandle: unknown,
    callback: (err: unknown, properties: ConnectionPropertiesCompat) => void) => void;
}

interface OperationPageParams {
  controlUrl: string;
  host: string;
  port: string;
  armConnected: boolean;
  armIp: string;
  armPort: string;
}

@Entry
@Component
struct Index {
  @State private deviceIp: string = '当前设备 IP：获取中...';
  @State private serverIp: string = '10.118.123.223';
  @State private serverPort: string = '5000';
  @State private armIp: string = '10.0.0.101';
  @State private armPort: string = '2000';
  @State private isOpening: boolean = false;
  @State private isArmConnecting: boolean = false;
  @State private isArmConnected: boolean = false;

  aboutToAppear(): void {
    this.loadDeviceIp();
    this.isArmConnected = robotArmClient.isConnected();
  }

  private loadDeviceIp(): void {
    const connectionApi = connection as unknown as ConnectionApiCompat;

    try {
      if (typeof connectionApi.getDefaultNetSync === 'function' &&
        typeof connectionApi.getConnectionPropertiesSync === 'function') {
        const netHandle = connectionApi.getDefaultNetSync();
        const properties = connectionApi.getConnectionPropertiesSync(netHandle);
        this.updateDeviceIpFromProperties(properties);
        return;
      }
    } catch (_err) {
    }

    if (typeof connectionApi.getDefaultNet === 'function' &&
      typeof connectionApi.getConnectionProperties === 'function') {
      connectionApi.getDefaultNet((netErr: unknown, netHandle: unknown) => {
        if (netErr) {
          this.deviceIp = '当前设备 IP：获取失败';
          return;
        }
        connectionApi.getConnectionProperties!(netHandle, (propertiesErr: unknown,
          properties: ConnectionPropertiesCompat) => {
          if (propertiesErr) {
            this.deviceIp = '当前设备 IP：获取失败';
            return;
          }
          this.updateDeviceIpFromProperties(properties);
        });
      });
      return;
    }

    this.deviceIp = '当前设备 IP：暂不支持';
  }

  private updateDeviceIpFromProperties(properties: ConnectionPropertiesCompat | undefined): void {
    const ipv4Address = this.extractIpv4Address(properties);
    this.deviceIp = `当前设备 IP：${ipv4Address || '未连接网络'}`;
  }

  private extractIpv4Address(properties: ConnectionPropertiesCompat | undefined): string {
    const linkAddresses = properties?.linkAddresses;
    if (!Array.isArray(linkAddresses)) {
      return '';
    }

    for (let index = 0; index < linkAddresses.length; index++) {
      const address = linkAddresses[index]?.address?.address;
      if (typeof address === 'string' && address.indexOf('.') >= 0) {
        return address;
      }
    }
    return '';
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (_err) {
    }
  }

  private buildControlUrl(ip: string, port: number): string {
    return `http://${ip}:${port}/`;
  }

  private openControlPage(): void {
    const ip = this.serverIp.trim();
    const port = Number(this.serverPort.trim());

    if (!ip || !Number.isInteger(port) || port < 1 || port > 65535) {
      this.showToast('请输入正确的上位机 IP 和端口');
      return;
    }

    this.isOpening = true;
    const params: OperationPageParams = {
      controlUrl: this.buildControlUrl(ip, port),
      host: ip,
      port: `${port}`,
      armConnected: this.isArmConnected,
      armIp: this.armIp.trim(),
      armPort: this.armPort.trim()
    };

    Promise.resolve(router.pushUrl({
      url: 'pages/OperationPage',
      params: params
    })).then(() => {
      this.isOpening = false;
    }).catch(() => {
      this.isOpening = false;
      this.showToast('打开操作台失败，请检查页面配置');
    });
  }

  private async toggleArmConnection(): Promise<void> {
    if (this.isArmConnected) {
      try {
        await robotArmClient.disconnect();
      } catch (_err) {
      }
      this.isArmConnected = false;
      this.showToast('已断开与机械臂的连接');
      return;
    }

    const ip = this.armIp.trim();
    const port = Number(this.armPort.trim());

    if (!ip || !Number.isInteger(port) || port < 1 || port > 65535) {
      this.showToast('请输入正确的机械臂 IP 和端口');
      return;
    }

    if (this.isArmConnecting) {
      return;
    }

    this.isArmConnecting = true;
    try {
      await robotArmClient.connect(ip, port);
      this.isArmConnected = true;
      this.showToast('成功连接到机械臂');
    } catch (_err) {
      this.isArmConnected = false;
      this.showToast('连接机械臂失败，请检查 IP 和端口');
    } finally {
      this.isArmConnecting = false;
    }
  }

  build() {
    Column({ space: 20 }) {
      Text('机械臂客户端')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)

      Text(this.deviceIp)
        .fontSize(14)
        .fontColor('#666666')
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 8, bottom: 12 })

      Column({ space: 14 }) {
        Text('上位机地址')
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F2937')

        Row({ space: 12 }) {
          TextInput({ placeholder: '上位机 IP', text: this.serverIp })
            .width('62%')
            .height(48)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.serverIp = value;
            })

          TextInput({ placeholder: '端口', text: this.serverPort })
            .type(InputType.Number)
            .width('26%')
            .height(48)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.serverPort = value;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding(18)
      .backgroundColor('#EEF2FF')
      .borderRadius(18)

      Column({ space: 14 }) {
        Text('机械臂地址')
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1F2937')

        Row({ space: 12 }) {
          TextInput({ placeholder: '机械臂 IP', text: this.armIp })
            .width('62%')
            .height(48)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.armIp = value;
            })

          TextInput({ placeholder: '端口', text: this.armPort })
            .type(InputType.Number)
            .width('26%')
            .height(48)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.armPort = value;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding(18)
      .backgroundColor('#FFF7ED')
      .borderRadius(18)

      Row({ space: 12 }) {
        Button(this.isArmConnecting ? '连接中...' : (this.isArmConnected ? '断开机械臂' : '连接机械臂'))
          .layoutWeight(1)
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .borderRadius(24)
          .backgroundColor(this.isArmConnecting ? '#9CA3AF' : (this.isArmConnected ? '#EF4444' : '#F59E0B'))
          .enabled(!this.isArmConnecting)
          .onClick(() => {
            this.toggleArmConnection();
          })

        Button(this.isOpening ? '打开中...' : '打开操作台')
          .layoutWeight(1)
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .borderRadius(24)
          .backgroundColor('#2563EB')
          .enabled(!this.isOpening)
          .onClick(() => {
            this.openControlPage();
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F7F8FA')
  }
}
