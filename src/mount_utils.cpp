#include "mount_utils.h"
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

#define LOG_TAG "MyRootHider"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace mount_utils {

const std::vector<std::string> ROOT_MOUNT_PATTERNS = {
    "/data/adb",
    "magisk",
    "zygisk",
    "riru",
    "lsposed",
    "/dev/.magisk",
    "/dev/zygisk",
    "/debug_ramdisk",
    "/sbin/.magisk",
};

const std::vector<std::string> HIDE_FILE_PATHS = {
    "/system/bin/su",
    "/system/xbin/su",
    "/sbin/su",
    "/system/bin/.magisk",
    "/system/bin/magisk",
    "/system/bin/magiskinit",
    "/system/bin/magiskpolicy",
    "/system/etc/init/magisk.rc",
    "/system/bin/daemonsu",
    "/system/bin/supolicy",
};

std::vector<MountInfo> parse_mountinfo() {
    std::vector<MountInfo> mounts;
    std::ifstream file("/proc/self/mountinfo");
    
    if (!file.is_open()) {
        LOGE("Failed to open /proc/self/mountinfo");
        return mounts;
    }
    
    std::string line;
    while (std::getline(file, line)) {
        MountInfo info;
        std::istringstream iss(line);
        
        if (!(iss >> info.mount_id >> info.parent_id)) continue;
        
        std::string major_minor;
        if (!(iss >> major_minor)) continue;
        if (!(iss >> info.root)) continue;
        
        // mount_point bisa mengandung spasi
        std::string mount_point;
        std::getline(iss, mount_point, ' ');
        if (!mount_point.empty() && mount_point[0] == ' ') {
            mount_point = mount_point.substr(1);
        }
        info.mount_point = mount_point;
        
        // Skip optional fields sampai tanda -
        std::string token;
        while (iss >> token) {
            if (token == "-") break;
        }
        
        if (!(iss >> info.fs_type)) continue;
        if (!(iss >> info.mount_source)) continue;
        
        mounts.push_back(info);
    }
    
    return mounts;
}

bool is_root_mount(const MountInfo& info) {
    for (const auto& pattern : ROOT_MOUNT_PATTERNS) {
        if (info.mount_point.find(pattern) != std::string::npos) return true;
        if (info.root.find(pattern) != std::string::npos) return true;
        if (info.mount_source.find(pattern) != std::string::npos) return true;
    }
    
    if (info.fs_type == "tmpfs" || info.fs_type == "overlay") {
        if (info.mount_point.find("/system") == 0 ||
            info.mount_point.find("/vendor") == 0 ||
            info.mount_point.find("/product") == 0 ||
            info.mount_point.find("/system_ext") == 0) {
            if (info.root.find("debug_ramdisk") != std::string::npos ||
                info.root.find("magisk") != std::string::npos) {
                return true;
            }
        }
    }
    
    return false;
}

int unmount_root_mounts() {
    auto mounts = parse_mountinfo();
    int unmounted = 0;
    
    for (auto it = mounts.rbegin(); it != mounts.rend(); ++it) {
        if (is_root_mount(*it)) {
            // Skip mount critical
            if (it->mount_point == "/" || 
                it->mount_point == "/system" ||
                it->mount_point == "/vendor" ||
                it->mount_point == "/data") {
                LOGD("Skipping critical mount: %s", it->mount_point.c_str());
                continue;
            }
            
            if (umount2(it->mount_point.c_str(), MNT_DETACH) == 0) {
                LOGI("Unmounted: %s", it->mount_point.c_str());
                unmounted++;
            } else {
                LOGD("Failed to unmount %s: %s", 
                     it->mount_point.c_str(), strerror(errno));
            }
        }
    }
    
    LOGI("Unmounted %d root-related mounts", unmounted);
    return unmounted;
}

int hide_files() {
    int hidden = 0;
    
    for (const auto& path : HIDE_FILE_PATHS) {
        struct stat st;
        if (stat(path.c_str(), &st) == 0) {
            if (mount("/dev/null", path.c_str(), nullptr, MS_BIND, nullptr) == 0) {
                LOGI("Hidden file: %s", path.c_str());
                hidden++;
            } else {
                LOGD("Failed to hide %s: %s", path.c_str(), strerror(errno));
            }
        }
    }
    
    LOGI("Hidden %d files", hidden);
    return hidden;
}

int setup_proc_filter() {
    int result = 0;
    result += proc_filter::filter_mountinfo();
    result += proc_filter::filter_maps();
    result += proc_filter::filter_mounts();
    return result;
}

} // namespace mount_utils
