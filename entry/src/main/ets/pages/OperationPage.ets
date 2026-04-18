import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import webview from '@ohos.web.webview';
import { robotArmClient } from '../common/RobotArmClient';

interface OperationPageParams {
  controlUrl?: string;
  host?: string;
  port?: string;
  armConnected?: boolean;
}

@Entry
@Component
struct OperationPage {
  @State private controlUrl: string = '';
  @State private hostLabel: string = '';
  @State private pageHint: string = '正在准备上位机操作台...';
  @State private armConnected: boolean = false;
  @State private gripperState: boolean = false;

  private readonly webController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    const params = router.getParams() as OperationPageParams;
    const url = this.normalizeUrl(typeof params?.controlUrl === 'string' ? params.controlUrl : '');
    const host = typeof params?.host === 'string' ? params.host : '';
    const port = typeof params?.port === 'string' ? params.port : '';

    this.controlUrl = url;
    this.hostLabel = host && port ? `${host}:${port}` : url;
    this.pageHint = url ? '正在加载上位机操作台...' : '未获取到上位机地址，请返回首页重新输入';
    this.armConnected = typeof params?.armConnected === 'boolean' ? params.armConnected : false;
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

  private goBack(): void {
    try {
      router.back();
    } catch (_err) {
      this.showToast('返回失败');
    }
  }

  private sendArmCommand(scriptCmd: string): void {
    if (!robotArmClient.isConnected()) {
      this.showToast('机械臂未连接');
      return;
    }
    robotArmClient.send(scriptCmd).then(() => {
      this.showToast(`已发送: ${scriptCmd}`);
    }).catch(() => {
      this.showToast('发送指令失败');
    });
  }

  build() {
    Column({ space: 16 }) {
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

      Column() {
        if (this.controlUrl) {
          Web({ src: this.controlUrl, controller: this.webController })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
        } else {
          Column({ space: 10 }) {
            Text(this.pageHint)
              .fontSize(18)
              .fontColor('#FFFFFF')
            Text('请返回首页重新填写上位机地址。')
              .fontSize(13)
              .fontColor('#D1D5DB')
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ left: 20, right: 20 })
      .backgroundColor('#111827')
      .borderRadius(18)
      .clip(true)

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
      .padding({ left: 20, right: 20, bottom: 8 })

      if (this.armConnected) {
        Row({ space: 12 }) {
          Button('夹爪闭合')
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .backgroundColor('#F59E0B')
            .onClick(() => {
              this.gripperState = true;
              this.sendArmCommand(`write_raw_data_485({1, 6, 1, 3, 0, 0, 120, 54})`);
            })

          Button('夹爪张开')
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .backgroundColor('#10B981')
            .onClick(() => {
              this.gripperState = false;
              this.sendArmCommand(`write_raw_data_485({1, 6, 1, 3, 3, -24, 120, -120})`);
            })

          Button('断开机械臂')
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .borderRadius(23)
            .backgroundColor('#EF4444')
            .onClick(async () => {
              try {
                await robotArmClient.disconnect();
              } catch (_err) {
              }
              this.armConnected = false;
              this.showToast('已断开与机械臂的连接');
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24 })
    .backgroundColor('#F7F8FA')
  }
}
