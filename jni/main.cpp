// QwennHide v2.0 - main.cpp
// Adapted from proven MagiskHideX architecture + Volume Button Mode Switcher

#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/mount.h>
#include <sys/socket.h>
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

#define DATADIR       "/data/adb/qwennhide"
#define MODE_FILE     DATADIR "/mode" // "basic" or "aggressive"
#define UMOUNT_LIST_F DATADIR "/umount_list"

static const char *MAGISK_PATHS[] = {
    "/sbin/.magisk", "/data/adb/magisk", "/data/adb/modules",
    "/data/adb/post-fs-data.d", "/data/adb/service.d",
    "/dev/.magisk", "/dev/.magisk.unblock", "/dev/zygisk", nullptr
};

static const char *SU_PATHS[] = {
    "/system/bin/su", "/system/xbin/su", "/sbin/su",
    "/system/bin/.ext/.su", "/system/usr/we-need-root/su", nullptr
};

static std::vector<std::string> readLines(const char *path) {
    std::vector<std::string> result;
    std::ifstream f(path);
    if (!f.is_open()) return result;
    std::string line;
    while (std::getline(f, line)) {
        if (!line.empty() && line[0] != '#') result.push_back(line);
    }
    return result;
}

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
            if (mountpoint.find(MAGISK_PATHS[i]) == 0 || mountpoint == MAGISK_PATHS[i]) {
                is_magisk = true; break;
            }
        }
        if (!is_magisk && (root.find("/magisk") != std::string::npos || root.find("/.magisk") != std::string::npos)) {
            is_magisk = true;
        }

        if (is_magisk) to_unmount.push_back({mount_id, mountpoint});
    }
    mi.close();

    for (auto it = to_unmount.rbegin(); it != to_unmount.rend(); ++it) {
        if (umount2(it->second.c_str(), MNT_DETACH) == 0) {
            LOGD("Unmounted: %s", it->second.c_str());
        }
    }
}

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

// ─── Companion Handler (Root Context) ─────────────────────────────────────────
static void companionHandler(int client_fd) {
    uint32_t len = 0;
    if (read(client_fd, &len, sizeof(len)) != sizeof(len) || len == 0 || len > 512) {
        uint8_t resp = 0; write(client_fd, &resp, 1); return;
    }

    std::string pkgName(len, '\0');
    if (read(client_fd, &pkgName[0], len) != (ssize_t)len) {
        uint8_t resp = 0; write(client_fd, &resp, 1); return;
    }

    bool aggressive_mode = false;
    std::ifstream mode_file(MODE_FILE);
    if (mode_file.is_open()) {
        std::string mode; std::getline(mode_file, mode);
        if (mode.find("aggressive") != std::string::npos) aggressive_mode = true;
    }

    uint8_t should_hide = 0;
    if (aggressive_mode) {
        // Aggressive: Check DenyList OR custom umount_list
        FILE *pipe = popen("magisk --denylist ls 2>/dev/null", "r");
        if (pipe) {
            char buf[256];
            while (fgets(buf, sizeof(buf), pipe)) {
                std::string entry(buf);
                if (!entry.empty() && entry.back() == '\n') entry.pop_back();
                size_t pipe_pos = entry.find('|');
                std::string entry_pkg = (pipe_pos != std::string::npos) ? entry.substr(0, pipe_pos) : entry;
                if (entry_pkg == pkgName) { should_hide = 1; break; }
            }
            pclose(pipe);
        }
        if (!should_hide) {
            for (auto &line : readLines(UMOUNT_LIST_F)) {
                if (line == pkgName) { should_hide = 1; break; }
            }
        }
    } else {
        // Basic: Rely purely on host's native PROCESS_ON_DENYLIST flag
        // We simulate this by returning 1 if we want the host to handle it, 
        // but actually, in Basic mode, we just let the host do its job via FORCE_DENYLIST_UNMOUNT.
        // To keep it simple and compatible, we check DenyList here too.
        FILE *pipe = popen("magisk --denylist ls 2>/dev/null", "r");
        if (pipe) {
            char buf[256];
            while (fgets(buf, sizeof(buf), pipe)) {
                std::string entry(buf);
                if (!entry.empty() && entry.back() == '\n') entry.pop_back();
                size_t pipe_pos = entry.find('|');
                std::string entry_pkg = (pipe_pos != std::string::npos) ? entry.substr(0, pipe_pos) : entry;
                if (entry_pkg == pkgName) { should_hide = 1; break; }
            }
            pclose(pipe);
        }
    }

    LOGI("Companion: [%s] mode=%s hide=%d", pkgName.c_str(), aggressive_mode ? "agg" : "basic", should_hide);
    write(client_fd, &should_hide, 1);
}

// ─── Main Module Class ────────────────────────────────────────────────────────
class QwennHide : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api = api; this->env = env;
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        should_hide = false;
        if (!args->nice_name) { api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); return; }

        const char *raw = env->GetStringUTFChars(args->nice_name, nullptr);
        if (!raw) { api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); return; }

        std::string pkg(raw);
        env->ReleaseStringUTFChars(args->nice_name, raw);
        size_t colon = pkg.find(':');
        if (colon != std::string::npos) pkg = pkg.substr(0, colon);

        int fd = api->connectCompanion();
        if (fd < 0) {
            LOGE("Companion connect failed");
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        uint32_t len = (uint32_t)pkg.size();
        write(fd, &len, sizeof(len));
        write(fd, pkg.c_str(), len);

        uint8_t resp = 0;
        read(fd, &resp, 1);
        close(fd);

        should_hide = (resp == 1);

        if (should_hide) {
            LOGI("Hiding root from: [%s]", pkg.c_str());
            api->setOption(zygisk::FORCE_DENYLIST_UNMOUNT);
        } else {
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        }
    }

    void postAppSpecialize(const zygisk::AppSpecializeArgs *args) override {
        if (!should_hide) return;

        // Aggressive cleanup (proven to work without triggering integrity checks)
        closeMagiskFds();
        unmountMagiskMounts();

        // Unload ourselves — leave no trace
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        LOGD("postAppSpecialize: hiding complete, unloading");
    }

    void preServerSpecialize(zygisk::ServerSpecializeArgs *args) override {
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

private:
    zygisk::Api *api = nullptr;
    JNIEnv *env = nullptr;
    bool should_hide = false;
};

REGISTER_ZYGISK_MODULE(QwennHide)
REGISTER_ZYGISK_COMPANION(companionHandler)
