#include "props.h"
#include "zygisk.hpp"

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <jni.h>

#ifndef QH_DEBUG
#define QH_DEBUG 0
#endif

#if QH_DEBUG
#include <android/log.h>
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "QH", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "QH", __VA_ARGS__)
#else
#define LOGI(...) ((void)0)
#define LOGE(...) ((void)0)
#endif

namespace qwennhide {

// ---- Original function pointers (saved before hooking) ----
static int  (*orig_system_property_get)(const char *, char *) = nullptr;
static int  (*orig_stat)(const char *, struct stat *) = nullptr;
static int  (*orig_access)(const char *, int) = nullptr;
static FILE *(*orig_fopen)(const char *, const char *) = nullptr;

// ---- Paths that must be invisible to the target app ----
static const char *HIDDEN_PATHS[] = {
    "/system/bin/su",
    "/system/xbin/su",
    "/sbin/su",
    "/sbin/.magisk",
    "/system/bin/.magisk",
    "/system/bin/magisk",
    "/system/bin/magiskinit",
    "/system/bin/magiskpolicy",
    "/data/adb",
    "/data/adb/magisk",
    "/data/adb/modules",
    "/data/adb/service.d",
    "/data/adb/post-fs-data.d",
    "/debug_ramdisk",
    "/dev/.magisk",
    "/dev/.magisk.unblock",
    "/dev/zygisk",
    nullptr,
};

static bool is_hidden_path(const char *path) {
    if (path == nullptr) return false;
    for (int i = 0; HIDDEN_PATHS[i] != nullptr; i++) {
        if (strcmp(path, HIDDEN_PATHS[i]) == 0) return true;
        // Also match subpaths: /data/adb/modules/xyz -> hidden
        size_t len = strlen(HIDDEN_PATHS[i]);
        if (strncmp(path, HIDDEN_PATHS[i], len) == 0 &&
            (path[len] == '/' || path[len] == '\0')) {
            return true;
        }
    }
    return false;
}

// ---- Hooked functions ----
static int fake_system_property_get(const char *name, char *value) {
    int len = orig_system_property_get(name, value);
    if (len <= 0 || value == nullptr) return len;

    auto spoof = [&](const char *v) {
        size_t n = strlen(v);
        if (n >= 91) n = 91; // PROP_VALUE_MAX
        memcpy(value, v, n);
        value[n] = '\0';
        return (int)n;
    };

    if (strcmp(name, "ro.build.tags") == 0)         return spoof("release-keys");
    if (strcmp(name, "ro.debuggable") == 0)         return spoof("0");
    if (strcmp(name, "ro.secure") == 0)             return spoof("1");
    if (strcmp(name, "ro.build.type") == 0)         return spoof("user");
    if (strcmp(name, "ro.build.selinux") == 0)      return spoof("0");
    if (strcmp(name, "ro.boot.verifiedbootstate") == 0) return spoof("green");
    if (strcmp(name, "ro.boot.vbmeta.device_state") == 0) return spoof("locked");
    if (strcmp(name, "ro.boot.veritymode") == 0)    return spoof("enforcing");
    if (strcmp(name, "ro.boot.flash.locked") == 0)  return spoof("1");
    if (strcmp(name, "persist.magisk.hide") == 0)   return spoof("0");
    if (strcmp(name, "persist.magisk.zygisk") == 0) return spoof("0");
    if (strncmp(name, "persist.qwennhide", 16) == 0) return spoof("");

    return len;
}

static int fake_stat(const char *path, struct stat *sb) {
    if (is_hidden_path(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_stat(path, sb);
}

static int fake_access(const char *path, int mode) {
    if (is_hidden_path(path)) {
        errno = ENOENT;
        return -1;
    }
    return orig_access(path, mode);
}

static FILE *fake_fopen(const char *path, const char *mode) {
    if (is_hidden_path(path)) {
        errno = ENOENT;
        return nullptr;
    }
    return orig_fopen(path, mode);
}

// ---- Public API ----
bool install_hooks() {
    // Hooks are installed by the module via Zygisk PLT API.
    // This function is a placeholder; actual registration is in main.cpp
    // because we need the Api* pointer.
    return true;
}

// ---- Accessors used by main.cpp ----
namespace hooks {
    int  (*system_property_get)(const char *, char *) = nullptr;
    int  (*stat_fn)(const char *, struct stat *) = nullptr;
    int  (*access_fn)(const char *, int) = nullptr;
    FILE *(*fopen_fn)(const char *, const char *) = nullptr;
}

} // namespace qwennhide
