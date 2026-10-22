#include "proc_filter.h"
#include <fstream>
#include <sstream>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <cstring>
#include <cerrno>
#include <android/log.h>
#include <vector>
#include <string>

#define LOG_TAG "SysOverlayPatch"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace proc_filter {

const char* FILTER_PATTERNS[] = {
    "magisk",
    "zygisk",
    "riru",
    "lsposed",
    "/data/adb",
    "/sbin/su",
    "/system/bin/su",
    "/system/xbin/su",
    "su.img",
    "magisk.img",
    "debug_ramdisk",
    ".magisk",
    "magiskinit",
    "magiskpolicy",
    "supersu",
    "superuser",
    "daemonsu",
    "com.android.system.overlay.patch", // Nama module baru
};

const int FILTER_PATTERN_COUNT = sizeof(FILTER_PATTERNS) / sizeof(FILTER_PATTERNS[0]);

bool should_filter_line(const std::string& line) {
    for (int i = 0; i < FILTER_PATTERN_COUNT; i++) {
        if (line.find(FILTER_PATTERNS[i]) != std::string::npos) {
            return true;
        }
    }
    return false;
}

int create_filtered_file(const char* source_path, const char* dest_path) {
    std::ifstream src(source_path);
    if (!src.is_open()) {
        LOGE("Failed to open source: %s", source_path);
        return -1;
    }
    
    std::ostringstream filtered;
    std::string line;
    int filtered_count = 0;
    
    bool is_status_file = (std::string(source_path) == "/proc/self/status");
    bool injected_tracer = false;
    
    while (std::getline(src, line)) {
        // Hardening: Paksa TracerPid menjadi 0
        if (is_status_file && line.find("TracerPid:") == 0) {
            filtered << "TracerPid:\t0\n";
            injected_tracer = true;
            filtered_count++;
            continue; // Skip baris asli
        }

        if (!should_filter_line(line)) {
            filtered << line << "\n";
        } else {
            filtered_count++;
        }
    }
    
    src.close();
    
    // Jika file status tapi tidak ada baris TracerPid sama sekali, tambahkan
    if (is_status_file && !injected_tracer) {
        filtered << "TracerPid:\t0\n";
    }
    
    // Gunakan path temp yang aman di /dev
    std::string tmp_path = std::string("/dev/.sys_tmp_") + 
                           std::to_string(getpid()) + "_" +
                           std::to_string(reinterpret_cast<uintptr_t>(dest_path) % 10000);
    
    std::ofstream dst(tmp_path);
    if (!dst.is_open()) {
        LOGE("Failed to create temp file: %s", tmp_path.c_str());
        return -1;
    }
    
    dst << filtered.str();
    dst.close();
    
    chmod(tmp_path.c_str(), 0444);
    
    if (mount(tmp_path.c_str(), dest_path, nullptr, MS_BIND, nullptr) != 0) {
        LOGE("Failed to bind mount %s -> %s: %s", tmp_path.c_str(), dest_path, strerror(errno));
        unlink(tmp_path.c_str());
        return -1;
    }
    
    unlink(tmp_path.c_str()); // Aman di-unlink setelah di-bind mount
    
    LOGI("Filtered %d lines from %s", filtered_count, source_path);
    return filtered_count;
}

int filter_mountinfo() {
    return create_filtered_file("/proc/self/mountinfo", "/proc/self/mountinfo");
}

int filter_maps() {
    return create_filtered_file("/proc/self/maps", "/proc/self/maps");
}

int filter_mounts() {
    return create_filtered_file("/proc/self/mounts", "/proc/self/mounts");
}

} // namespace proc_filter
