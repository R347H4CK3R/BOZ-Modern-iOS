from pathlib import Path
import shutil
shutil.copyfile("src/BOZDiagnostics.m", "repair/src/BOZDiagnostics.m")
p=Path("repair/build-fixed-ipa.sh")
s=p.read_text()
assert s.count('-framework CoreGraphics -framework Foundation -framework UIKit') == 1
s=s.replace('-framework CoreGraphics -framework Foundation -framework UIKit', '-framework CoreGraphics -framework Foundation -framework UIKit -framework Security')
assert s.count('"$fullscreen_fix_source"') == 1
s=s.replace('"$fullscreen_fix_source"', '"$fullscreen_fix_source" "$script_dir/src/BOZDiagnostics.m"')
p.write_text(s)
p=Path("repair/src/BOZFullscreenFix.m")
s=p.read_text()
s=s.replace('#import <Foundation/Foundation.h>', '#import <Foundation/Foundation.h>\nextern void BOZDiagnosticLog(NSString *message);')
s=s.replace('static void BOZGLViewShow(id self, SEL selector)\n{', 'static void BOZGLViewShow(id self, SEL selector)\n{\n    static BOOL firstFrame = YES;\n    if (firstFrame) { firstFrame = NO; BOZDiagnosticLog(@"render=first-frame-enter"); }')
s=s.replace('NSLog(@"[BOZFullscreenFix] installed full-bleed CIwUIView safe-root hook");','BOZDiagnosticLog(@"render=guest-vtable-hook-installed");')
s=s.replace('        BOZPublishSafeMetrics();\n        NSLog(', '        BOZPublishSafeMetrics();\n        BOZDiagnosticLog(@"fullscreen-constructor=ready");\n        NSLog(')
p.write_text(s)
print("Diagnostics integrated with renderer checkpoints")
