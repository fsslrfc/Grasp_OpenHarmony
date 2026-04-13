import socket from '@ohos.net.socket';
import util from '@ohos.util';

export interface DetectionTarget {
  id: number;
  class_name: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface TcpFramePacket {
  image: string;
  list: DetectionTarget[];
}

export type PacketListener = (packet: TcpFramePacket) => void;

interface PacketSource {
  image?: string;
  list?: TargetSource[];
}

interface TargetSource {
  id?: number;
  class_name?: string;
  x?: number;
  y?: number;
  w?: number;
  h?: number;
}

class TcpClientService {
  private client: any = null;
  private decoder = util.TextDecoder.create('utf-8');
  private readonly packetListeners: PacketListener[] = [];
  private receiveBuffer: number[] = [];
  private latestPacket: TcpFramePacket | null = null;
  private connected: boolean = false;

  private readonly messageHandler = (info: { message: ArrayBuffer }): void => {
    const messageBytes = new Uint8Array(info.message);
    for (let index = 0; index < messageBytes.length; index++) {
      this.receiveBuffer.push(messageBytes[index]);
    }
    this.consumeBuffer();
  };

  private readonly connectHandler = (): void => {
    this.connected = true;
  };

  private readonly closeHandler = (): void => {
    this.connected = false;
  };

  private readonly errorHandler = (_err: unknown): void => {
    this.connected = false;
  };

  async connect(ip: string, port: number, timeout: number = 5000): Promise<void> {
    await this.disconnect();
    this.resetStreamState();

    const client = socket.constructTCPSocketInstance();
    client.on('message', this.messageHandler);
    client.on('connect', this.connectHandler);
    client.on('close', this.closeHandler);
    client.on('error', this.errorHandler);
    this.client = client;

    try {
      await client.connect({
        address: {
          address: ip,
          family: 1,
          port: port
        },
        timeout: timeout
      });
      this.connected = true;
    } catch (err) {
      this.connected = false;
      this.unregisterClientEvents(client);
      await this.safeCloseClient(client);
      if (this.client === client) {
        this.client = null;
      }
      throw err;
    }
  }

  async disconnect(): Promise<void> {
    const currentClient = this.client;
    this.client = null;
    this.connected = false;
    this.resetStreamState();

    if (!currentClient) {
      return;
    }

    this.unregisterClientEvents(currentClient);
    await this.safeCloseClient(currentClient);
  }

  subscribePacket(listener: PacketListener): void {
    if (this.packetListeners.indexOf(listener) < 0) {
      this.packetListeners.push(listener);
    }
  }

  unsubscribePacket(listener: PacketListener): void {
    const index = this.packetListeners.indexOf(listener);
    if (index >= 0) {
      this.packetListeners.splice(index, 1);
    }
  }

  getLatestPacket(): TcpFramePacket | null {
    return this.latestPacket;
  }

  isConnected(): boolean {
    return this.connected;
  }

  private consumeBuffer(): void {
    while (true) {
      const splitIndex = this.receiveBuffer.indexOf(10);
      if (splitIndex < 0) {
        return;
      }

      const lineBytes = this.receiveBuffer.slice(0, splitIndex);
      this.receiveBuffer = this.receiveBuffer.slice(splitIndex + 1);
      const line = this.decoder.decode(Uint8Array.from(lineBytes)).trim();
      if (!line) {
        continue;
      }

      const packet = this.parsePacket(line);
      if (!packet) {
        continue;
      }

      this.latestPacket = packet;
      this.notifyPacketListeners(packet);
    }
  }

  private parsePacket(line: string): TcpFramePacket | null {
    try {
      const source = JSON.parse(line) as PacketSource;
      const targets: DetectionTarget[] = [];

      if (Array.isArray(source.list)) {
        source.list.forEach((item: TargetSource) => {
          const target = this.parseTarget(item);
          if (target !== null) {
            targets.push(target);
          }
        });
      }

      return {
        image: typeof source.image === 'string' ? source.image : '',
        list: targets
      };
    } catch (_err) {
      return null;
    }
  }

  private parseTarget(source: TargetSource | null | undefined): DetectionTarget | null {
    if (!source) {
      return null;
    }

    return {
      id: this.toNumber(source.id),
      class_name: typeof source.class_name === 'string' ? source.class_name : 'unknown',
      x: this.toNumber(source.x),
      y: this.toNumber(source.y),
      w: this.toNumber(source.w),
      h: this.toNumber(source.h)
    };
  }

  private toNumber(value: number | undefined): number {
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
  }

  private notifyPacketListeners(packet: TcpFramePacket): void {
    this.packetListeners.forEach((listener: PacketListener) => {
      listener(packet);
    });
  }

  private resetStreamState(): void {
    this.decoder = util.TextDecoder.create('utf-8');
    this.receiveBuffer = [];
    this.latestPacket = null;
  }

  private unregisterClientEvents(client: any): void {
    client.off('message', this.messageHandler);
    client.off('connect', this.connectHandler);
    client.off('close', this.closeHandler);
    client.off('error', this.errorHandler);
  }

  private async safeCloseClient(client: any): Promise<void> {
    try {
      await client.close();
    } catch (_err) {
    }
  }
}

export const tcpClientService = new TcpClientService();
