import 'uue_file_types.dart';
import 'uue_files_native.dart'
    if (dart.library.js_interop) 'uue_files_web.dart'
    as platform;
export 'uue_file_types.dart';

UueFiles uueFiles = platform.PlatformUueFiles();
