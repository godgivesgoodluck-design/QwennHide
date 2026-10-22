#include "props.h"
#include "zygisk.hpp"

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <cerrno>
#include <cstdarg>
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

static int  (*orig_system_property_get)(const char *, char *) = nullptr;
static int  (*orig_stat)(const char *, struct stat *) = nullptr;
static int  (*orig_lstat)(const char *, struct stat *) = nullptr;
static int  (*orig_access)(const char *, int) = nullptr;
static int  (*orig_faccessat)(int, const char *, int, int) = nullptr;
static int  (*orig_open)(const char *, int, ...) = nullptr;
static int  (*orig_openat)(int, const char *, int, ...) = nullptr;
static ssize_t (*orig_readlink)(const char *, char *, size_t) = nullptr;
static FILE *(*orig_fopen)(const char *, const char *) = nullptr;

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

bool is_hidden_path(const char *path) {
    if (path == nullptr) return false;
    for (int i = 0; HIDDEN_PATHS[i] != nullptr; i++) {
        const char *hp = HIDDEN_PATHS[i];
        size_t len = strlen(hp);
        if (strcmp(path, hp) == 0) return true;
        if (strncmp(path, hp, len) == 0 &&
            (path[len] == '/' || path[len] == '\0')) {
            return true;
        }
    }
    return false;
}

int fake_system_property_get(const char *name, char *value) {
    int len = orig_system_property_get(name, value);
    if (len <= 0 || value == nullptr) return len;

    auto spoof = [&](const char *v) {
        size_t n = strlen(v);
        if (n >= 91) n = 91;
        memcpy(value, v, n);
        value[n] = '\0';
        return (int)n;
    };

    if (strcmp(name, "ro.build.tags") == 0)              return spoof("release-keys");
    if (strcmp(name, "ro.debuggable") == 0)              return spoof("0");
    if (strcmp(name, "ro.secure") == 0)                  return spoof("1");
    if (strcmp(name, "ro.build.type") == 0)              return spoof("user");
    if (strcmp(name, "ro.build.selinux") == 0)           return spoof("0");
    if (strcmp(name, "ro.boot.verifiedbootstate") == 0)  return spoof("green");
    if (strcmp(name, "ro.boot.vbmeta.device_state") == 0) return spoof("locked");
    if (strcmp(name, "ro.boot.veritymode") == 0)         return spoof("enforcing");
    if (strcmp(name, "ro.boot.flash.locked") == 0)       return spoof("1");
    if (strcmp(name, "persist.magisk.hide") == 0)        return spoof("0");
    if (strcmp(name, "persist.magisk.zygisk") == 0)      return spoof("0");
    if (strncmp(name, "persist.qwennhide", 16) == 0)     return spoof("");

    return len;
}

int fake_stat(const char *path, struct stat *sb) {
    if (is_hidden_path(path)) { errno = ENOENT; return -1; }
    return orig_stat(path, sb);
}

int fake_lstat(const char *path, struct stat *sb) {
    if (is_hidden_path(path)) { errno = ENOENT; return -1; }
    return orig_lstat(path, sb);
}

int fake_access(const char *path, int mode) {
    if (is_hidden_path(path)) { errno = ENOENT; return -1; }
    return orig_access(path, mode);
}

int fake_faccessat(int dirfd, const char *path, int mode, int flags) {
    if (is_hidden_path(path)) { errno = ENOENT; return -1; }
    return orig_faccessat(dirfd, path, mode, flags);
}

int fake_open(const char *path, int flags, ...) {
    if (is_hidden_path(path)) { errno = ENOENT; return -1; }
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = va_arg(args, mode_t);
        va_end(args);
    }
    return orig_open(path, flags, mode);
}

int fake_openat(int dirfd, const char *path, int flags, ...) {
    if (is_hidden_path(path)) { errno = ENOENT; return -1; }
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode = va_arg(args, mode_t);
        va_end(args);
    }
    return orig_openat(dirfd, path, flags, mode);
}

ssize_t fake_readlink(const char *path, char *buf, size_t bufsiz) {
    if (path != nullptr && strcmp(path, "/proc/self/exe") == 0) {
        const char *fake = "/system/bin/app_process64";
        size_t len = strlen(fake);
        if (len >= bufsiz) len = bufsiz - 1;
        memcpy(buf, fake, len);
        buf[len] = '\0';
        return (ssize_t)len;
    }
    if (is_hidden_path(path)) { errno = ENOENT; return -1; }
    return orig_readlink(path, buf, bufsiz);
}

FILE *fake_fopen(const char *path, const char *mode) {
    if (is_hidden_path(path)) { errno = ENOENT; return nullptr; }
    return orig_fopen(path, mode);
}

bool install_hooks() { return true; }

namespace hooks {
    int  (*system_property_get)(const char *, char *) = nullptr;
    int  (*stat_fn)(const char *, struct stat *) = nullptr;
    int  (*lstat_fn)(const char *, struct stat *) = nullptr;
    int  (*access_fn)(const char *, int) = nullptr;
    int  (*faccessat_fn)(int, const char *, int, int) = nullptr;
    int  (*open_fn)(const char *, int, ...) = nullptr;
    int  (*openat_fn)(int, const char *, int, ...) = nullptr;
    ssize_t (*readlink_fn)(const char *, char *, size_t) = nullptr;
    FILE *(*fopen_fn)(const char *, const char *) = nullptr;
}

} // namespace qwennhide
