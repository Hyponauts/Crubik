import '../../../domain/smart_cube_device.dart';
import '../../ble/ble_central.dart';
import '../smart_cube_adapter.dart';

final class KnownMoyuRecognizer implements CubeDeviceRecognizer {
  const KnownMoyuRecognizer();

  @override
  CubeDeviceMatch? match(BleAdvertisement advertisement) {
    final name = advertisement.displayName.toUpperCase();
    if (name.startsWith('WCU_MY3')) {
      return const CubeDeviceMatch(
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.moyu32,
        supportStatus: CubeSupportStatus.detectedUnsupported,
        supportMessage:
            'This WCU MoYu cube uses the MoYu32 protocol, which is detected but not supported yet.',
      );
    }
    if (name.startsWith('MHC')) {
      return const CubeDeviceMatch(
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.moyuMhc,
        supportStatus: CubeSupportStatus.detectedUnsupported,
        supportMessage:
            'MoYu MHC cubes such as the WeiLong V10 AI are detected, but their protocol is not supported yet.',
      );
    }
    if (name.startsWith('MOYU')) {
      return const CubeDeviceMatch(
        vendor: CubeVendor.moyu,
        protocolFamily: CubeProtocolFamily.unknown,
        supportStatus: CubeSupportStatus.detectedUnsupported,
        supportMessage:
            'This MoYu model is detected, but only the MoYu AI 2023 protocol is supported currently.',
      );
    }
    return null;
  }
}
