import socket from '@ohos.net.socket';
import connection from '@ohos.net.connection';

export type RobotArmMessageListener = (data: string) => void;

class RobotArmClientService {
  private client: socket.TCPSocket | null = null;
  private connected: boolean = false;
  private readonly messageListeners: RobotArmMessageListener[] = [];

  isConnected(): boolean {
    return this.connected;
  }

  /**
   * 将 socket 绑定到目标 IP 所在子网对应的网络接口（如 eth1），
   * 解决 OpenHarmony 策略路由（table 106）将流量劫持到 wlan0 的问题。
   */
  private async bindSocketToTargetNetwork(client: socket.TCPSocket, targetIp: string): Promise<void> {
    const netHandles = await connection.getAllNets();
    for (const netHandle of netHandles) {
      const linkInfo = await connection.getConnectionProperties(netHandle);
      const ifaceLinks = linkInfo.linkAddresses || [];
      for (const link of ifaceLinks) {
        const localIp = link.address.address;
        if (this.isSameSubnet(localIp, targetIp, link.prefixLength)) {
          console.info(`[RobotArmClient] Found matching network: netId=${netHandle.netId}, iface=${localIp}/${link.prefixLength}`);
          await netHandle.bindSocket(client);
          console.info('[RobotArmClient] Socket bound to target network via NetHandle.bindSocket()');
          return;
        }
      }
    }
    console.warn('[RobotArmClient] No matching network found for target IP, falling back to default route');
  }

  /**
   * 判断两个 IP 是否在同一子网
   */
  private isSameSubnet(ip1: string, ip2: string, prefixLength: number): boolean {
    const toNum = (ip: string): number =>
      ip.split('.').reduce((acc: number, octet: string) => (acc << 8) + parseInt(octet, 10), 0) >>> 0;
    const mask = prefixLength === 0 ? 0 : (~0 << (32 - prefixLength)) >>> 0;
    return (toNum(ip1) & mask) === (toNum(ip2) & mask);
  }

  async connect(ip: string, port: number, timeout: number = 5000): Promise<void> {
    await this.disconnect();

    const client = socket.constructTCPSocketInstance();
    try {
      // 先通过 NetHandle.bindSocket 将 socket 绑定到目标网络，确保流量从正确的网卡出去
      await this.bindSocketToTargetNetwork(client, ip);
    } catch (err) {
      console.error('[RobotArmClient] bindSocket failed:', JSON.stringify(err));
    }
    this.client = client;

    client.on('message', (value: { message: ArrayBuffer }) => {
      const dataStr = String.fromCharCode.apply(null, new Uint8Array(value.message));
      this.notifyMessageListeners(dataStr);
    });

    client.on('close', () => {
      this.connected = false;
    });

    client.on('error', () => {
      this.connected = false;
    });

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
      console.error(err);
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

    if (!currentClient) {
      return;
    }

    this.unregisterClientEvents(currentClient);
    await this.safeCloseClient(currentClient);
  }

  async send(scriptCmd: string, isCommand: boolean = true): Promise<void> {
    if (!this.client || !this.connected) {
      throw new Error('机械臂未连接');
    }
    const payload = isCommand ? `<start>${scriptCmd}<end>` : scriptCmd;
    await this.client.send({ data: payload });
  }

  subscribeMessage(listener: RobotArmMessageListener): void {
    if (this.messageListeners.indexOf(listener) < 0) {
      this.messageListeners.push(listener);
    }
  }

  unsubscribeMessage(listener: RobotArmMessageListener): void {
    const index = this.messageListeners.indexOf(listener);
    if (index >= 0) {
      this.messageListeners.splice(index, 1);
    }
  }

  private notifyMessageListeners(data: string): void {
    this.messageListeners.forEach((listener: RobotArmMessageListener) => {
      listener(data);
    });
  }

  private unregisterClientEvents(client: socket.TCPSocket): void {
    client.off('message');
    client.off('close');
    client.off('error');
  }

  private async safeCloseClient(client: socket.TCPSocket): Promise<void> {
    try {
      await client.close();
    } catch (_err) {
    }
  }
}

export const robotArmClient = new RobotArmClientService();
