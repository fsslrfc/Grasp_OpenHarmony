import image from '@ohos.multimedia.image';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import util from '@ohos.util';
import type { DetectionTarget, PacketListener, TcpFramePacket } from '../common/TcpClient';
import { tcpClientService } from '../common/TcpClient';

@Entry
@Component
struct OperationPage {
  @State private framePixelMap: image.PixelMap | undefined = undefined;
  @State private targets: DetectionTarget[] = [];
  @State private videoHint: string = '等待视频流...';

  private readonly base64Helper: util.Base64Helper = new util.Base64Helper();
  private pendingBase64: string | null = null;
  private isDecoding: boolean = false;
  private cleanedUp: boolean = false;

  private readonly packetListener: PacketListener = (packet: TcpFramePacket): void => {
    this.targets = packet.list;
    this.enqueueFrameDecode(packet.image);
  };

  aboutToAppear(): void {
    this.cleanedUp = false;
    const latestPacket = tcpClientService.getLatestPacket();
    if (latestPacket) {
      this.targets = latestPacket.list;
      this.enqueueFrameDecode(latestPacket.image);
    } else {
      this.videoHint = tcpClientService.isConnected() ? '等待视频流...' : '连接已断开';
    }
    tcpClientService.subscribePacket(this.packetListener);
  }

  aboutToDisappear(): void {
    tcpClientService.unsubscribePacket(this.packetListener);
    this.cleanupConnection();
  }

  private enqueueFrameDecode(base64Image: string): void {
    if (!base64Image) {
      return;
    }

    this.pendingBase64 = base64Image;
    if (this.isDecoding) {
      return;
    }

    this.isDecoding = true;
    this.consumePendingFrame();
  }

  private async consumePendingFrame(): Promise<void> {
    while (this.pendingBase64) {
      const currentBase64 = this.pendingBase64;
      this.pendingBase64 = null;
      try {
        await this.updateFrame(currentBase64);
      } catch (_err) {
        this.videoHint = '图像解码失败';
      }
    }
    this.isDecoding = false;
  }

  private async updateFrame(base64Image: string): Promise<void> {
    const normalizedBase64 = this.normalizeBase64(base64Image);
    if (!normalizedBase64) {
      return;
    }

    const decodedBytes = this.base64Helper.decodeSync(normalizedBase64);
    const imageBuffer = decodedBytes.buffer.slice(
      decodedBytes.byteOffset,
      decodedBytes.byteOffset + decodedBytes.byteLength
    );
    const imageSource = image.createImageSource(imageBuffer);

    try {
      const pixelMap = await imageSource.createPixelMap();
      const previousFrame = this.framePixelMap;
      this.framePixelMap = pixelMap;
      this.videoHint = '视频流接收中';
      if (previousFrame) {
        await previousFrame.release();
      }
    } finally {
      await imageSource.release();
    }
  }

  private normalizeBase64(base64Image: string): string {
    const trimmed = base64Image.trim();
    const commaIndex = trimmed.indexOf(',');
    return commaIndex >= 0 ? trimmed.slice(commaIndex + 1) : trimmed;
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (_err) {
    }
  }

  private async disconnectAndBack(): Promise<void> {
    await this.cleanupConnection();
    try {
      router.back();
    } catch (_err) {
    }
  }

  private async cleanupConnection(): Promise<void> {
    if (this.cleanedUp) {
      return;
    }

    this.cleanedUp = true;
    this.pendingBase64 = null;
    try {
      await tcpClientService.disconnect();
    } catch (_err) {
      this.showToast('断开连接失败');
    }
    await this.releaseCurrentFrame();
  }

  private async releaseCurrentFrame(): Promise<void> {
    const currentFrame = this.framePixelMap;
    this.framePixelMap = undefined;
    if (!currentFrame) {
      return;
    }

    try {
      await currentFrame.release();
    } catch (_err) {
    }
  }

  private formatNumber(value: number): string {
    return value.toFixed(2);
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          if (this.framePixelMap) {
            Image(this.framePixelMap)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)
          } else {
            Text(this.videoHint)
              .fontSize(18)
              .fontColor('#FFFFFF')
          }
        }
        .width('90%')
        .aspectRatio(4 / 3)
        .borderRadius(16)
        .clip(true)
        .backgroundColor('#1F2937')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      List({ space: 12 }) {
        if (this.targets.length > 0) {
          ForEach(this.targets, (item: DetectionTarget) => {
            ListItem() {
              Row() {
                Text(`${item.id}  ${item.class_name}`)
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#222222')
                  .layoutWeight(1)
                  .textAlign(TextAlign.Start)

                Column({ space: 4 }) {
                  Text(`x: ${this.formatNumber(item.x)}  y: ${this.formatNumber(item.y)}`)
                    .fontSize(12)
                    .fontColor('#666666')
                  Text(`w: ${this.formatNumber(item.w)}  h: ${this.formatNumber(item.h)}`)
                    .fontSize(12)
                    .fontColor('#666666')
                }
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#FFFFFF')
              .borderRadius(14)
            }
          }, (item: DetectionTarget) => `${item.id}-${item.class_name}`)
        } else {
          ListItem() {
            Text('当前暂无检测目标')
              .width('100%')
              .fontSize(15)
              .fontColor('#999999')
              .textAlign(TextAlign.Center)
              .padding(20)
              .backgroundColor('#FFFFFF')
              .borderRadius(14)
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 20, right: 20 })

      Row() {
        Button('断开连接')
          .width('90%')
          .height(48)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .borderRadius(24)
          .backgroundColor('#E84040')
          .onClick(() => {
            this.disconnectAndBack();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 24, bottom: 24 })
    .backgroundColor('#F7F8FA')
  }
}
