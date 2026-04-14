import connection from '@ohos.net.connection';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';

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
}

@Entry
@Component
struct Index {
  @State private deviceIp: string = '当前设备 IP：获取中...';
  @State private serverIp: string = '10.109.10.223';
  @State private serverPort: string = '5000';
  @State private isOpening: boolean = false;

  aboutToAppear(): void {
    this.loadDeviceIp();
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
      port: `${port}`
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

  build() {
    Column({ space: 20 }) {
      Text('机械臂客户端')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)

      Text('下位机仅负责加载上位机视觉操作台页面')
        .fontSize(15)
        .fontColor('#4B5563')
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

        Text('默认访问 `http://上位机IP:端口/`，页面内的视频、识别结果和点击交互均由上位机统一处理。')
          .fontSize(13)
          .fontColor('#6B7280')
          .width('100%')
          .lineHeight(20)
      }
      .width('100%')
      .padding(18)
      .backgroundColor('#EEF2FF')
      .borderRadius(18)

      Button(this.isOpening ? '打开中...' : '打开操作台')
        .width(220)
        .height(48)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .borderRadius(24)
        .enabled(!this.isOpening)
        .onClick(() => {
          this.openControlPage();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F7F8FA')
  }
}
