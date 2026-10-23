// QwennHide v2.1 - main.cpp
// Optimized for GSI + Safe SU Isolation

#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <android/log.h>
#include <vector>
#include <string>
#include <fstream>
#include <sstream>

#include "zygisk.hpp"

#define LOG_TAG "QwennHide"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

#define DATADIR   "/data/adb/qwennhide"
#define MODE_FILE DATADIR "/mode"

static const char *MAGISK_PATHS[] = {
    "/sbin/.magisk", "/data/adb/magisk", "/data/adb/modules",
    "/dev/.magisk", "/dev/.magisk.unblock", "/dev/zygisk", nullptr
};

static const char *SU_PATHS[] = {
    "/system/bin/su", "/system/xbin/su", "/sbin/su",
    "/system/bin/.ext/.su", nullptr
};

// ─── Utility: Close Leaked FDs ─────────────────────────────────────────
static void closeMagiskFds() {
    DIR *fd_dir = opendir("/proc/self/fd");
    if (!fd_dir) return;

    struct dirent *entry;
    while ((entry = readdir(fd_dir)) != nullptr) {
        if (entry->d_name[0] == '.') continue;
        int fd = atoi(entry->d_name);
        if (fd <= 2) continue;

        char link_path[64], target[512];
        snprintf(link_path, sizeof(link_path), "/proc/self/fd/%s", entry->d_name);
        ssize_t len = readlink(link_path, target, sizeof(target) - 1);
        if (len <= 0) continue;
        target[len] = '\0';

        for (int i = 0; MAGISK_PATHS[i]; i++) {
            if (strncmp(target, MAGISK_PATHS[i], strlen(MAGISK_PATHS[i])) == 0) {
                close(fd); LOGD("Closed Magisk fd %d", fd); break;
            }
        }
        for (int i = 0; SU_PATHS[i]; i++) {
            if (strcmp(target, SU_PATHS[i]) == 0) {
                close(fd); LOGD("Closed su fd %d", fd); break;
            }
        }
    }
    closedir(fd_dir);
}

// ─── Utility: Manual Unmount Fallback ──────────────────────────────────
static void unmountMagiskMounts() {
    std::ifstream mi("/proc/self/mountinfo");
    if (!mi.is_open()) return;

    std::vector<std::pair<int, std::string>> to_unmount;
    std::string line;

    while (std::getline(mi, line)) {
        std::istringstream ss(line);
        int mount_id, parent_id;
        std::string major_minor, root, mountpoint;
        ss >> mount_id >> parent_id >> major_minor >> root >> mountpoint;

        bool is_magisk = false;
        for (int i = 0; MAGISK_PATHS[i]; i++) {
            if (mountpoint.find(MAGISK_PATHS[i]) == 0) { is_magisk = true; break; }
        }
        if (!is_magisk && root.find("magisk") != std::string::npos) is_magisk = true;

        if (is_magisk) to_unmount.push_back({mount_id, mountpoint});
    }
    mi.close();

    for (auto it = to_unmount.rbegin(); it != to_unmount.rend(); ++it) {
        if (umount2(it->second.c_str(), MNT_DETACH) == 0) {
            LOGD("Unmounted: %s", it->second.c_str());
        }
    }
}

// ─── Companion Handler (Root Context) ──────────────────────────────────
// Mengirim: 0 = Skip, 1 = Basic Hide, 2 = Aggressive Hide
static void companionHandler(int client_fd) {
    uint32_t len = 0;
    if (read(client_fd, &len, sizeof(len)) != sizeof(len) || len == 0 || len > 512) {
        uint8_t resp = 0; write(client_fd, &resp, 1); return;
    }

    std::string pkgName(len, '\0');
    read(client_fd, &pkgName[0], len);

    // Baca Mode (Aman karena di konteks root)
    std::string mode = "basic";
    std::ifstream mf(MODE_FILE);
    if (mf.is_open()) std::getline(mf, mode);
    bool is_aggressive = (mode.find("aggressive") != std::string::npos);

    // Cek DenyList Magisk
    bool in_denylist = false;
    FILE *pipe = popen("magisk --denylist ls 2>/dev/null", "r");
    if (pipe) {
        char buf[256];
        while (fgets(buf, sizeof(buf), pipe)) {
            std::string entry(buf);
            if (!entry.empty() && entry.back() == '\n') entry.pop_back();
            size_t pipe_pos = entry.find('|');
            std::string entry_pkg = (pipe_pos != std::string::npos) ? entry.substr(0, pipe_pos) : entry;
            if (entry_pkg == pkgName) { in_denylist = true; break; }
        }
        pclose(pipe);
    }

    uint8_t action = 0;
    if (in_denylist) {
        action = is_aggressive ? 2 : 1;
    }

    LOGI("Companion: [%s] in_denylist=%d mode=%s -> action=%d", 
         pkgName.c_str(), in_denylist, mode.c_str(), action);
    
    write(client_fd, &action, 1);
}

// ─── Main Module ───────────────────────────────────────────────────────
class QwennHide : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api = api; this->env = env;
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        hide_action = 0;
        if (!args->nice_name) { api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); return; }

        const char *raw = env->GetStringUTFChars(args->nice_name, nullptr);
        if (!raw) { api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); return; }

        std::string pkg(raw);
        env->ReleaseStringUTFChars(args->nice_name, raw);
        size_t colon = pkg.find(':');
        if (colon != std::string::npos) pkg = pkg.substr(0, colon);

        // Tanya Companion
        int fd = api->connectCompanion();
        if (fd < 0) { api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); return; }

        uint32_t len = (uint32_t)pkg.size();
        write(fd, &len, sizeof(len));
        write(fd, pkg.c_str(), len);

        uint8_t resp = 0;
        read(fd, &resp, 1);
        close(fd);

        hide_action = resp; // 0=Skip, 1=Basic, 2=Aggressive

        if (hide_action > 0) {
            LOGI("Hiding [%s] mode=%d", pkg.c_str(), hide_action);
            // Ini adalah kunci "SU Isolation":
            // Memaksa Magisk melakukan unmount semua overlay & su dari namespace app ini
            api->setOption(zygisk::FORCE_DENYLIST_UNMOUNT);
        } else {
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        }
    }

    void postAppSpecialize([[maybe_unused]] const zygisk::AppSpecializeArgs *args) override {
        if (hide_action == 0) return;

        if (hide_action == 2) {
            // Aggressive: Tambahan cleanup manual
            LOGD("Aggressive cleanup: FDs + Mounts");
            closeMagiskFds();
            unmountMagiskMounts();
        }

        // Unload module agar tidak ada jejak di /proc/self/maps
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

    void preServerSpecialize([[maybe_unused]] zygisk::ServerSpecializeArgs *args) override {
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

private:
    zygisk::Api *api = nullptr;
    JNIEnv *env = nullptr;
    uint8_t hide_action = 0;
};

REGISTER_ZYGISK_MODULE(QwennHide)
REGISTER_ZYGISK_COMPANION(companionHandler)
