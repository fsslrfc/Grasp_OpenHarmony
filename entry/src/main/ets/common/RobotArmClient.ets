import socket from '@ohos.net.socket';
import util from '@ohos.util';

export type RobotArmMessageListener = (data: string) => void;
export type RobotArmConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error';
export type RobotArmConnectionListener = (state: RobotArmConnectionState, detail?: string) => void;

export type RobotJoints = [number, number, number, number, number, number];
export type RobotPose = [number, number, number, number, number, number];
export type RobotOrientation = [number, number, number];

export const DEFAULT_ROBOT_ORIENTATION: RobotOrientation = [-3.14, 0, -1.57];


export interface RobotJointMoveOptions {
  speed?: number;
  acceleration?: number;
  radius?: number;
  block?: boolean;
}

export interface RobotPoseMoveOptions {
  speed?: number;
  acceleration?: number;
  radius?: number;
  block?: boolean;
  qnear?: RobotJoints;
  tool?: string;
  wobj?: string;
}

export interface RobotPointActionOptions extends RobotPoseMoveOptions {
  approachOffsetZ?: number;
  speedPercent?: number;
}

export interface RobotMotionDefaults {
  jointSpeed: number;
  jointAcceleration: number;
  linearSpeed: number;
  linearAcceleration: number;
  radius: number;
  block: boolean;
  tool: string;
  wobj: string;
  qnear: RobotJoints;
  orientation: RobotOrientation;
  approachOffsetZ: number;
}

interface ResolvedJointMoveOptions {
  speed: number;
  acceleration: number;
  radius: number;
  block: boolean;
}

interface ResolvedPoseSharedOptions {
  radius: number;
  block: boolean;
  qnear?: RobotJoints;
  tool: string;
  wobj: string;
}

interface ResolvedPoseMoveOptions extends ResolvedPoseSharedOptions {
  speed: number;
  acceleration: number;
}

interface ResolvedPointActionOptions extends ResolvedPoseSharedOptions {
  approachOffsetZ: number;
  speedPercent: number;
  jointSpeed: number;
  jointAcceleration: number;
  linearSpeed: number;
  linearAcceleration: number;
}


class RobotCommandBuilder {
  wrap(script: string): string {
    return `<start>${script}<end>`;
  }

  compose(scripts: string[], sleepAfterEachMs?: number): string {
    const resolvedScripts = scripts.filter((script: string) => script.trim().length > 0);
    if (typeof sleepAfterEachMs !== 'number' || !Number.isFinite(sleepAfterEachMs) || sleepAfterEachMs <= 0) {
      return resolvedScripts.join('\n');
    }
    const composedScripts: string[] = [];
    resolvedScripts.forEach((script: string) => {
      composedScripts.push(script);
      composedScripts.push(this.sleep(sleepAfterEachMs));
    });
    return composedScripts.join('\n');
  }

  speed(percent: number): string {


    return `speed(${this.formatNumber(percent)})`;
  }

  sleep(milliseconds: number): string {
    return `sleep(${this.formatMilliseconds(milliseconds)})`;
  }

  stop(): string {

    return 'stop';
  }

  pause(): string {
    return 'pause';
  }

  resume(): string {
    return 'resume';
  }

  powerOn(): string {
    return 'poweron';
  }

  enable(): string {
    return 'enable';
  }

  disable(): string {
    return 'disable';
  }

  powerOff(): string {
    return 'poweroff';
  }


  moveJ2(joints: RobotJoints, speed: number, acceleration: number, radius: number, block: boolean): string {
    return `movej2(${this.formatVector(joints)},${this.formatNumber(speed)},${this.formatNumber(acceleration)},${this.formatNumber(radius)},${this.formatBoolean(block)})`;
  }

  moveJPose2(pose: RobotPose, speed: number, acceleration: number, radius: number,
    qnear: RobotJoints | undefined, tool: string, wobj: string): string {
    return `movej_pose2(${this.formatVector(pose)},${this.formatNumber(speed)},${this.formatNumber(acceleration)},${this.formatNumber(radius)},${this.formatOptionalVector(qnear)},${this.formatText(tool)},${this.formatText(wobj)})`;
  }

  moveL(pose: RobotPose, speed: number, acceleration: number, radius: number,
    qnear: RobotJoints | undefined, tool: string, wobj: string): string {
    return `movel(${this.formatVector(pose)},${this.formatNumber(speed)},${this.formatNumber(acceleration)},${this.formatNumber(radius)},${this.formatOptionalVector(qnear)},${this.formatText(tool)},${this.formatText(wobj)})`;
  }


  gripperInit(): string {
    return 'write_raw_data_485({1, 6, 1, 0, 0, 1, 73, -10})';
  }

  gripperClose(): string {
    return 'write_raw_data_485({1, 6, 1, 3, 0, 0, 120, 54})';
  }

  gripperOpen(): string {
    return 'write_raw_data_485({1, 6, 1, 3, 3, -24, 120, -120})';
  }

  gripperForce20(): string {
    return 'write_raw_data_485({1,6,1,1,0,20,217,249})';
  }

  gripperForce60(): string {
    return 'write_raw_data_485({1,6,1,1,0,60,217,231})';
  }

  gripperForce100(): string {
    return 'write_raw_data_485({1,6,1,1,0,100,216,29})';
  }

  private formatVector(values: RobotJoints | RobotPose): string {

    return `{${values.map((value: number) => this.formatNumber(value)).join(',')}}`;
  }

  private formatOptionalVector(values?: RobotJoints): string {
    return values ? this.formatVector(values) : '{}';
  }


  private formatText(value: string): string {

    const escaped = value.replace(/"/g, '\\"');
    return `"${escaped}"`;
  }

  private formatBoolean(value: boolean): string {
    return value ? 'true' : 'false';
  }

  private formatNumber(value: number): string {
    if (!Number.isFinite(value)) {
      return '0';
    }
    return `${Number(value.toFixed(6))}`;
  }

  private formatMilliseconds(value: number): string {
    if (!Number.isFinite(value) || value <= 0) {
      return '0';
    }
    return `${Math.round(value)}`;
  }
}


class RobotArmClientService {
  private client: socket.TCPSocket | null = null;
  private connected: boolean = false;
  private connectionState: RobotArmConnectionState = 'disconnected';
  private lastError: string = '';
  private decoder = util.TextDecoder.create('utf-8');
  private readonly messageListeners: RobotArmMessageListener[] = [];
  private readonly connectionListeners: RobotArmConnectionListener[] = [];
  private readonly builder: RobotCommandBuilder = new RobotCommandBuilder();
  private gripperForcePercent: number = 20;
  private motionDefaults: RobotMotionDefaults = {

    jointSpeed: 0.5,
    jointAcceleration: 1,
    linearSpeed: 0.5,
    linearAcceleration: 1,

    radius: 0,
    block: false,
    tool: 'default',
    wobj: 'default',
    qnear: [0, 0, 1.57, 0, -1.57, 0],
    orientation: [DEFAULT_ROBOT_ORIENTATION[0], DEFAULT_ROBOT_ORIENTATION[1], DEFAULT_ROBOT_ORIENTATION[2]],
    approachOffsetZ: 0.08

  };

  isConnected(): boolean {
    return this.connected;
  }

  getConnectionState(): RobotArmConnectionState {
    return this.connectionState;
  }

  getLastError(): string {
    return this.lastError;
  }

  getMotionDefaults(): RobotMotionDefaults {
    return {
      jointSpeed: this.motionDefaults.jointSpeed,
      jointAcceleration: this.motionDefaults.jointAcceleration,
      linearSpeed: this.motionDefaults.linearSpeed,
      linearAcceleration: this.motionDefaults.linearAcceleration,
      radius: this.motionDefaults.radius,
      block: this.motionDefaults.block,
      tool: this.motionDefaults.tool,
      wobj: this.motionDefaults.wobj,
      qnear: this.cloneJoints(this.motionDefaults.qnear),
      orientation: this.cloneOrientation(this.motionDefaults.orientation),
      approachOffsetZ: this.motionDefaults.approachOffsetZ
    };
  }

  setMotionDefaults(defaults: Partial<RobotMotionDefaults>): void {
    if (typeof defaults.jointSpeed === 'number' && Number.isFinite(defaults.jointSpeed)) {
      this.motionDefaults.jointSpeed = defaults.jointSpeed;
    }
    if (typeof defaults.jointAcceleration === 'number' && Number.isFinite(defaults.jointAcceleration)) {
      this.motionDefaults.jointAcceleration = defaults.jointAcceleration;
    }
    if (typeof defaults.linearSpeed === 'number' && Number.isFinite(defaults.linearSpeed)) {
      this.motionDefaults.linearSpeed = defaults.linearSpeed;
    }
    if (typeof defaults.linearAcceleration === 'number' && Number.isFinite(defaults.linearAcceleration)) {
      this.motionDefaults.linearAcceleration = defaults.linearAcceleration;
    }
    if (typeof defaults.radius === 'number' && Number.isFinite(defaults.radius)) {
      this.motionDefaults.radius = defaults.radius;
    }
    if (typeof defaults.block === 'boolean') {
      this.motionDefaults.block = defaults.block;
    }
    if (typeof defaults.tool === 'string' && defaults.tool.trim()) {
      this.motionDefaults.tool = defaults.tool.trim();
    }
    if (typeof defaults.wobj === 'string' && defaults.wobj.trim()) {
      this.motionDefaults.wobj = defaults.wobj.trim();
    }
    if (this.isVector6(defaults.qnear)) {
      this.motionDefaults.qnear = this.asJoints(defaults.qnear);
    }
    if (this.isVector3(defaults.orientation)) {
      this.motionDefaults.orientation = this.asOrientation(defaults.orientation);
    }
    if (typeof defaults.approachOffsetZ === 'number' && Number.isFinite(defaults.approachOffsetZ)) {
      this.motionDefaults.approachOffsetZ = defaults.approachOffsetZ;
    }
  }

  async connect(ip: string, port: number, timeout: number = 5000): Promise<void> {
    await this.disconnect();
    this.updateConnectionState('connecting');
    this.decoder = util.TextDecoder.create('utf-8');

    const client = socket.constructTCPSocketInstance();
    this.client = client;

    client.on('message', (value: { message: ArrayBuffer }) => {
      const data = this.decoder.decode(new Uint8Array(value.message));
      this.notifyMessageListeners(data);
    });

    client.on('close', () => {
      if (this.client === client) {
        this.client = null;
      }
      this.updateConnectionState('disconnected');
    });

    client.on('error', (err: unknown) => {
      this.updateConnectionState('error', this.stringifyError(err));
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
      this.updateConnectionState('connected');
    } catch (err) {
      this.unregisterClientEvents(client);
      await this.safeCloseClient(client);
      if (this.client === client) {
        this.client = null;
      }
      this.updateConnectionState('error', this.stringifyError(err));
      throw err;
    }
  }

  async disconnect(): Promise<void> {
    const currentClient = this.client;
    this.client = null;
    this.decoder = util.TextDecoder.create('utf-8');
    this.updateConnectionState('disconnected');

    if (!currentClient) {
      return;
    }

    this.unregisterClientEvents(currentClient);
    await this.safeCloseClient(currentClient);
  }

  async sendRaw(payload: string): Promise<void> {
    this.ensureConnected();
    await this.client!.send({ data: payload });
  }

  async setSpeed(percent: number): Promise<void> {
    await this.sendRaw(this.builder.speed(this.clampSpeedPercent(percent)));
  }

  async sleep(milliseconds: number): Promise<void> {
    await this.sendWrappedScript(this.builder.sleep(milliseconds));
  }

  async stop(): Promise<void> {

    await this.sendRaw(this.builder.stop());
  }

  async pause(): Promise<void> {
    await this.sendRaw(this.builder.pause());
  }

  async resume(): Promise<void> {
    await this.sendRaw(this.builder.resume());
  }

  async powerOn(): Promise<void> {
    await this.sendRaw(this.builder.powerOn());
  }

  async enable(): Promise<void> {
    await this.sendRaw(this.builder.enable());
  }

  async disable(): Promise<void> {
    await this.sendRaw(this.builder.disable());
  }

  async powerOff(): Promise<void> {
    await this.sendRaw(this.builder.powerOff());
  }


  async moveJ2(joints: RobotJoints, options?: RobotJointMoveOptions): Promise<void> {
    const resolved = this.resolveJointMoveOptions(options);
    await this.sendWrappedScript(this.builder.moveJ2(
      joints,
      resolved.speed,
      resolved.acceleration,
      resolved.radius,
      resolved.block
    ));
  }

  async moveToPose(pose: RobotPose, options?: RobotPoseMoveOptions): Promise<void> {
    await this.sendWrappedScript(this.buildMoveToPoseScript(pose, options));
  }

  async moveLine(pose: RobotPose, options?: RobotPoseMoveOptions): Promise<void> {
    await this.sendWrappedScript(this.buildMoveLineScript(pose, options));
  }




  async initGripper(): Promise<void> {
    await this.sendWrappedScript(this.builder.gripperInit());
  }

  async closeGripper(): Promise<void> {
    await this.sendWrappedScript(this.builder.gripperClose());
  }

  async openGripper(): Promise<void> {
    await this.sendWrappedScript(this.builder.gripperOpen());
  }

  async setGripperForce(forcePercent: number): Promise<void> {
    const resolvedForcePercent = forcePercent >= 100 ? 100 : (forcePercent >= 60 ? 60 : 20);
    const script = resolvedForcePercent >= 100
      ? this.builder.gripperForce100()
      : (resolvedForcePercent >= 60 ? this.builder.gripperForce60() : this.builder.gripperForce20());
    await this.sendWrappedScript(script);
    this.gripperForcePercent = resolvedForcePercent;
  }


  async graspAtPoint(x: number, y: number, z: number, options?: RobotPointActionOptions): Promise<void> {

    const resolved = this.resolvePointActionOptions(options);
    const targetPose = this.buildPose(x, y, z);
    await this.sendWrappedScript(this.builder.compose(this.buildPointActionScripts(targetPose, true, resolved)));
  }

  async placeAtPoint(x: number, y: number, z: number, options?: RobotPointActionOptions): Promise<void> {
    const resolved = this.resolvePointActionOptions(options);
    const targetPose = this.buildPose(x, y, z);
    await this.sendWrappedScript(this.builder.compose(this.buildPointActionScripts(targetPose, false, resolved)));
  }

  async pickAndPlacePoints(pickPose: RobotPose, placePose: RobotPose, options?: RobotPointActionOptions): Promise<void> {
    const resolved = this.resolvePointActionOptions(options);
    await this.sendWrappedScript(this.builder.compose([
      ...this.buildPointActionScripts(pickPose, true, resolved),
      ...this.buildPointActionScripts(placePose, false, resolved)
    ]));
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

  subscribeStatus(listener: RobotArmConnectionListener): void {
    if (this.connectionListeners.indexOf(listener) < 0) {
      this.connectionListeners.push(listener);
      listener(this.connectionState, this.lastError);
    }
  }

  unsubscribeStatus(listener: RobotArmConnectionListener): void {
    const index = this.connectionListeners.indexOf(listener);
    if (index >= 0) {
      this.connectionListeners.splice(index, 1);
    }
  }

  private buildPointActionScripts(targetPose: RobotPose, closeGripper: boolean,
    options: ResolvedPointActionOptions): string[] {
    const actionPose = closeGripper ? targetPose : this.offsetPose(targetPose, 0, 0, 0.005);
    const retreatPose = actionPose;
    const hasApproach = Math.abs(options.approachOffsetZ) > 0;
    const approachPose = hasApproach
      ? this.offsetPose(retreatPose, 0, 0, options.approachOffsetZ)
      : null;


    const jointMoveOptions: RobotPoseMoveOptions = {
      speed: options.jointSpeed,
      acceleration: options.jointAcceleration,
      radius: options.radius,
      qnear: options.qnear,
      tool: options.tool,
      wobj: options.wobj
    };
    const linearMoveOptions: RobotPoseMoveOptions = {
      speed: options.linearSpeed,
      acceleration: options.linearAcceleration,
      radius: options.radius,
      qnear: options.qnear,
      tool: options.tool,
      wobj: options.wobj
    };
    const scripts: string[] = [closeGripper ? this.builder.gripperOpen() : this.builder.gripperClose()];
    scripts.push(this.builder.sleep(this.resolveGraspSleepMilliseconds()));

    if (approachPose) {

      scripts.push(this.buildMoveToPoseScript(approachPose, jointMoveOptions));
      scripts.push(this.buildMoveLineScript(actionPose, linearMoveOptions));
    } else {
      scripts.push(this.buildMoveToPoseScript(actionPose, jointMoveOptions));
    }

    scripts.push(closeGripper ? this.builder.gripperClose() : this.builder.gripperOpen());
    scripts.push(this.builder.sleep(this.resolveGraspSleepMilliseconds()));

    if (approachPose) {
      scripts.push(this.buildMoveLineScript(approachPose, linearMoveOptions));
    }


    return scripts;
  }


  private buildMoveToPoseScript(pose: RobotPose, options?: RobotPoseMoveOptions): string {
    const resolved = this.resolveJointPoseMoveOptions(options);
    return this.builder.moveJPose2(
      pose,
      resolved.speed,
      resolved.acceleration,
      resolved.radius,
      resolved.qnear,
      resolved.tool,
      resolved.wobj
    );
  }

  private buildMoveLineScript(pose: RobotPose, options?: RobotPoseMoveOptions): string {
    const resolved = this.resolveLinearPoseMoveOptions(options);
    return this.builder.moveL(
      pose,
      resolved.speed,
      resolved.acceleration,
      resolved.radius,
      resolved.qnear,
      resolved.tool,
      resolved.wobj
    );
  }

  private buildPose(x: number, y: number, z: number): RobotPose {

    return [
      this.toFiniteNumber(x),
      this.toFiniteNumber(y),
      this.toFiniteNumber(z),
      this.motionDefaults.orientation[0],
      this.motionDefaults.orientation[1],
      this.motionDefaults.orientation[2]
    ];
  }

  private offsetPose(pose: RobotPose, dx: number, dy: number, dz: number): RobotPose {
    return [
      pose[0] + dx,
      pose[1] + dy,
      pose[2] + dz,
      pose[3],
      pose[4],
      pose[5]
    ];
  }

  private resolveJointMoveOptions(options?: RobotJointMoveOptions): ResolvedJointMoveOptions {
    return {
      speed: this.resolveFiniteNumber(options?.speed, this.motionDefaults.jointSpeed),
      acceleration: this.resolveFiniteNumber(options?.acceleration, this.motionDefaults.jointAcceleration),
      radius: this.resolveFiniteNumber(options?.radius, this.motionDefaults.radius),
      block: typeof options?.block === 'boolean' ? options.block : this.motionDefaults.block
    };
  }

  private resolvePoseSharedOptions(options?: RobotPoseMoveOptions): ResolvedPoseSharedOptions {
    return {
      radius: this.resolveFiniteNumber(options?.radius, this.motionDefaults.radius),
      block: typeof options?.block === 'boolean' ? options.block : this.motionDefaults.block,
      qnear: undefined,
      tool: typeof options?.tool === 'string' && options.tool.trim() ? options.tool.trim() : this.motionDefaults.tool,
      wobj: typeof options?.wobj === 'string' && options.wobj.trim() ? options.wobj.trim() : this.motionDefaults.wobj
    };
  }

  private resolveJointPoseMoveOptions(options?: RobotPoseMoveOptions): ResolvedPoseMoveOptions {
    const shared = this.resolvePoseSharedOptions(options);
    return {
      speed: this.resolveFiniteNumber(options?.speed, this.motionDefaults.jointSpeed),
      acceleration: this.resolveFiniteNumber(options?.acceleration, this.motionDefaults.jointAcceleration),
      radius: shared.radius,
      block: shared.block,
      qnear: shared.qnear,
      tool: shared.tool,
      wobj: shared.wobj
    };
  }

  private resolveLinearPoseMoveOptions(options?: RobotPoseMoveOptions): ResolvedPoseMoveOptions {
    const shared = this.resolvePoseSharedOptions(options);
    return {
      speed: this.resolveFiniteNumber(options?.speed, this.motionDefaults.linearSpeed),
      acceleration: this.resolveFiniteNumber(options?.acceleration, this.motionDefaults.linearAcceleration),
      radius: shared.radius,
      block: shared.block,
      qnear: shared.qnear,
      tool: shared.tool,
      wobj: shared.wobj
    };
  }

  private resolvePointActionOptions(options?: RobotPointActionOptions): ResolvedPointActionOptions {
    const shared = this.resolvePoseSharedOptions(options);
    return {
      radius: shared.radius,
      block: shared.block,
      qnear: shared.qnear,
      tool: shared.tool,
      wobj: shared.wobj,
      approachOffsetZ: this.resolveFiniteNumber(options?.approachOffsetZ, this.motionDefaults.approachOffsetZ),
      speedPercent: this.clampSpeedPercent(this.resolveFiniteNumber(options?.speedPercent, 30)),
      jointSpeed: this.motionDefaults.jointSpeed,
      jointAcceleration: this.motionDefaults.jointAcceleration,
      linearSpeed: this.resolveFiniteNumber(options?.speed, this.motionDefaults.linearSpeed),
      linearAcceleration: this.resolveFiniteNumber(options?.acceleration, this.motionDefaults.linearAcceleration)
    };
  }


  private async sendWrappedScript(script: string): Promise<void> {
    await this.sendRaw(this.builder.wrap(script));
  }

  private ensureConnected(): void {
    if (!this.client || !this.connected) {
      throw new Error('机械臂未连接');
    }
  }

  private updateConnectionState(state: RobotArmConnectionState, detail: string = ''): void {
    this.connectionState = state;
    this.connected = state === 'connected';
    this.lastError = state === 'error' ? detail : '';
    this.notifyConnectionListeners(state, this.lastError);
  }

  private notifyMessageListeners(data: string): void {
    this.messageListeners.forEach((listener: RobotArmMessageListener) => {
      listener(data);
    });
  }

  private notifyConnectionListeners(state: RobotArmConnectionState, detail: string): void {
    this.connectionListeners.forEach((listener: RobotArmConnectionListener) => {
      listener(state, detail);
    });
  }

  private stringifyError(err: unknown): string {
    if (err instanceof Error && err.message) {
      return err.message;
    }
    if (typeof err === 'string') {
      return err;
    }
    try {
      return JSON.stringify(err);
    } catch (_jsonErr) {
      return 'unknown_error';
    }
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

  private resolveFiniteNumber(value: number | undefined, fallback: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
  }

  private resolveGraspSleepMilliseconds(): number {
    if (this.gripperForcePercent >= 100) {
      return 1000;
    }
    if (this.gripperForcePercent >= 60) {
      return 2000;
    }
    return 3000;
  }

  private clampSpeedPercent(value: number): number {

    if (!Number.isFinite(value)) {
      return 30;
    }
    if (value <= 0) {
      return 1;
    }
    if (value > 100) {
      return 100;
    }
    return value;
  }

  private toFiniteNumber(value: number): number {
    return Number.isFinite(value) ? value : 0;
  }

  private cloneJoints(values: RobotJoints): RobotJoints {
    return [values[0], values[1], values[2], values[3], values[4], values[5]];
  }

  private cloneOrientation(values: RobotOrientation): RobotOrientation {
    return [values[0], values[1], values[2]];
  }

  private isVector6(values: number[] | undefined): values is RobotJoints {
    return Array.isArray(values) && values.length === 6 && values.every((value: number) => Number.isFinite(value));
  }

  private isVector3(values: number[] | undefined): values is RobotOrientation {
    return Array.isArray(values) && values.length === 3 && values.every((value: number) => Number.isFinite(value));
  }

  private asJoints(values: number[]): RobotJoints {
    return [values[0], values[1], values[2], values[3], values[4], values[5]];
  }

  private asOrientation(values: number[]): RobotOrientation {
    return [values[0], values[1], values[2]];
  }
}

export const robotArmClient = new RobotArmClientService();
