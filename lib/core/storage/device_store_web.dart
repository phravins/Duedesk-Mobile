import 'package:hive_ce_flutter/hive_flutter.dart';
import '../config/environment.dart';
import 'local_store.dart';

/// Browsers cannot write to the drive directly, so on the web the device
/// workspace stays in the browser's own storage. The [key] is not used here:
/// a browser would have to keep it beside the data, which protects nothing.
Future<LocalStore> openDeviceStore(List<int> key) async => HiveLocalStore(
  await Hive.openBox<String>('${AppConfig.environmentName}-workspace'),
  await Hive.openBox<List<int>>('${AppConfig.environmentName}-files'),
);
