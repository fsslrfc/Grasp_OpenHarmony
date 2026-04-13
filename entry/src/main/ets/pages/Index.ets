import connection from '@ohos.net.connection';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import { tcpClientService } from '../common/TcpClient';

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

@Entry
@Component
struct Index {
  @State private deviceIp: string = '当前设备 IP：获取中...';
  @State private serverIp: string = '';
  @State private serverPort: string = '';
  @State private isConnecting: boolean = false;

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

  private connectToServer(): void {
    const ip = this.serverIp.trim();
    const port = Number(this.serverPort.trim());

    if (!ip || !Number.isInteger(port) || port < 1 || port > 65535) {
      this.showToast('请输入正确的 IP 和端口');
      return;
    }

    this.isConnecting = true;
    tcpClientService.connect(ip, port, 5000)
      .then(() => {
        this.isConnecting = false;
        router.pushUrl({ url: 'pages/OperationPage' });
      })
      .catch(() => {
        this.isConnecting = false;
        tcpClientService.disconnect().catch(() => {
        });
        this.showToast('连接失败，请检查网络与服务端');
      });
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
        .margin({ top: 20, bottom: 20 })

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

      Button(this.isConnecting ? '连接中...' : '连接')
        .width(220)
        .height(48)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .borderRadius(24)
        .enabled(!this.isConnecting)
        .onClick(() => {
          this.connectToServer();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F7F8FA')
  }
}
