#!/usr/bin/env python3
"""Resolve fixed game offsets from its own Objective-C method, never image 0."""
from pathlib import Path
p = Path("repair/src/BOZFullscreenFix.m")
s = p.read_text()
s = s.replace("#import <mach-o/dyld.h>", "#import <mach-o/dyld.h>\n#import <dlfcn.h>\n#import <string.h>")
old = """    const struct mach_header *header = _dyld_get_image_header(0);
    if (header == NULL) {
        return NULL;
    }
    return (void *)((uintptr_t)header + offset);"""
new = """    // LiveContainer loads the guest alongside its host. Image zero is then
    // the host, so fixed BOZ offsets must be anchored to the guest image.
    if (g_originalGLViewShow == NULL) {
        return NULL;
    }
    Dl_info info = {0};
    if (dladdr((const void *)g_originalGLViewShow, &info) == 0 ||
        info.dli_fbase == NULL) {
        return NULL;
    }
    const char *classImage = class_getImageName(objc_getClass("GLView"));
    if (classImage == NULL || info.dli_fname == NULL ||
        strcmp(classImage, info.dli_fname) != 0) {
        return NULL;
    }
    const struct mach_header *header = info.dli_fbase;
    if (header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64) {
        return NULL;
    }
    return (void *)((uintptr_t)header + offset);"""
assert s.count(old) == 1, "Pinned source no longer matches"
s = s.replace(old, new)
assert "_dyld_get_image_header(0)" not in s
p.write_text(s)
print("Installed fail-closed guest image resolution")
