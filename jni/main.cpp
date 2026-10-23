// ═══════════════════════════════════════════════════════════════════════
// QwennHide — jni/main.cpp (FINAL + WebUI per-app config)
//
// Modes:
//   0 = Skip, 1 = Basic, 2 = Aggressive, 3 = Persistent
// Config:
//   /data/adb/qwennhide/mode        → default global
//   /data/adb/qwennhide/apps.list   → override per-app (pkg|mode)
//   /data/adb/qwennhide/prop_spoof  → dibaca service.sh, bukan di sini
// ═══════════════════════════════════════════════════════════════════════

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
#define APPS_FILE DATADIR "/apps.list"

// ─── Paths ─────────────────────────────────────────────────────────────
static const char *FD_CHECK_PATHS[] = {
    "/sbin/.magisk", "/data/adb/magisk", "/data/adb/modules",
    "/system/bin/su", "/system/xbin/su", "/sbin/su",
    "/system/bin/.ext/.su", nullptr
};

static const char *UNMOUNT_PATHS[] = {
    "/sbin/.magisk", "/data/adb/magisk", "/data/adb/modules",
    "/dev/.magisk", "/dev/.magisk.unblock", nullptr
};

static const char *NEOZYGISK_CLEANUP_PATHS[] = {
    "/dev/zygisk", "/dev/neozygisk", "/dev/zygisksu", nullptr
};

// ─── String helpers ────────────────────────────────────────────────────
static std::string trimStr(const std::string &s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

static std::string readFirstLine(const char *path) {
    std::ifstream f(path);
    std::string line;
    if (std::getline(f, line)) return trimStr(line);
    return "";
}

// ─── Config readers ────────────────────────────────────────────────────
static std::string getDefaultMode() {
    std::string m = readFirstLine(MODE_FILE);
    if (m != "basic" && m != "aggressive" && m != "persistent") m = "basic";
    return m;
}

static std::string getAppMode(const std::string &pkg) {
    std::ifstream f(APPS_FILE);
    std::string result;
    if (f.is_open()) {
        std::string line;
        while (std::getline(f, line)) {
            line = trimStr(line);
            if (line.empty() || line[0] == '#') continue;
            size_t sep = line.find('|');
            if (sep == std::string::npos) continue;
            std::string key = trimStr(line.substr(0, sep));
            std::string val = trimStr(line.substr(sep + 1));
            if (key == pkg) result = val; // entry terakhir menang
        }
    }
    if (!result.empty()) return result;
    return getDefaultMode();
}

// ─── Cleanup utilities ─────────────────────────────────────────────────
static void closeLeakedFds() {
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
        for (int i = 0; FD_CHECK_PATHS[i]; i++) {
            if (strncmp(target, FD_CHECK_PATHS[i], strlen(FD_CHECK_PATHS[i])) == 0) {
                close(fd);
                LOGD("Closed leaked fd %d -> %s", fd, target);
                break;
            }
        }
    }
    closedir(fd_dir);
}

static void manualUnmount() {
    std::ifstream mi("/proc/self/mountinfo");
    if (!mi.is_open()) return;
    std::vector<std::pair<int, std::string>> to_unmount;
    std::string line;
    while (std::getline(mi, line)) {
        std::istringstream ss(line);
        int mount_id, parent_id;
        std::string major_minor, root, mountpoint;
        ss >> mount_id >> parent_id >> major_minor >> root >> mountpoint;
        bool should_unmount = false;
        for (int i = 0; UNMOUNT_PATHS[i]; i++) {
            if (mountpoint.find(UNMOUNT_PATHS[i]) == 0) { should_unmount = true; break; }
        }
        if (mountpoint.find("/dev/zygisk") == 0 ||
            mountpoint.find("/dev/neozygisk") == 0 ||
            mountpoint.find("/dev/zygisksu") == 0 ||
            mountpoint.find("/data/adb/modules/neozygisk") == 0 ||
            mountpoint.find("/data/adb/modules/zygisksu") == 0) {
            should_unmount = false;
        }
        if (should_unmount) to_unmount.push_back({mount_id, mountpoint});
    }
    mi.close();
    for (auto it = to_unmount.rbegin(); it != to_unmount.rend(); ++it) {
        if (umount2(it->second.c_str(), MNT_DETACH) == 0) {
            LOGD("Manual unmount: %s", it->second.c_str());
        }
    }
}

static void cleanNeoZygiskTraces() {
    LOGD("Cleaning NeoZygisk traces");
    DIR *fd_dir = opendir("/proc/self/fd");
    if (fd_dir) {
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
            for (int i = 0; NEOZYGISK_CLEANUP_PATHS[i]; i++) {
                if (strncmp(target, NEOZYGISK_CLEANUP_PATHS[i],
                            strlen(NEOZYGISK_CLEANUP_PATHS[i])) == 0) {
                    close(fd);
                    LOGD("Closed NeoZygisk fd %d", fd);
                    break;
                }
            }
        }
        closedir(fd_dir);
    }

    std::ifstream mi("/proc/self/mountinfo");
    if (!mi.is_open()) return;
    std::vector<std::pair<int, std::string>> to_unmount;
    std::string line;
    while (std::getline(mi, line)) {
        std::istringstream ss(line);
        int mount_id, parent_id;
        std::string major_minor, root, mountpoint;
        ss >> mount_id >> parent_id >> major_minor >> root >> mountpoint;
        for (int i = 0; NEOZYGISK_CLEANUP_PATHS[i]; i++) {
            if (mountpoint.find(NEOZYGISK_CLEANUP_PATHS[i]) == 0) {
                to_unmount.push_back({mount_id, mountpoint});
                break;
            }
        }
    }
    mi.close();
    for (auto it = to_unmount.rbegin(); it != to_unmount.rend(); ++it) {
        if (umount2(it->second.c_str(), MNT_DETACH) == 0) {
            LOGD("Unmounted NeoZygisk: %s", it->second.c_str());
        }
    }
}

// ─── DenyList check (multi-source) ─────────────────────────────────────
static bool isInDenyList(const std::string &pkg) {
    FILE *pipe = popen("magisk --denylist ls 2>/dev/null", "r");
    if (pipe) {
        char buf[256];
        while (fgets(buf, sizeof(buf), pipe)) {
            std::string entry(buf);
            if (!entry.empty() && entry.back() == '\n') entry.pop_back();
            size_t sep = entry.find('|');
            std::string entry_pkg = (sep != std::string::npos) ? entry.substr(0, sep) : entry;
            if (entry_pkg == pkg) { pclose(pipe); return true; }
        }
        pclose(pipe);
    }

    const char *neo_paths[] = {
        "/data/adb/modules/neozygisk/denylist",
        "/data/adb/modules/zygisksu/denylist",
        nullptr
    };
    for (int i = 0; neo_paths[i]; i++) {
        std::ifstream f(neo_paths[i]);
        if (!f.is_open()) continue;
        std::string line;
        while (std::getline(f, line)) {
            if (line.empty() || line[0] == '#') continue;
            size_t sep = line.find('|');
            std::string p = (sep != std::string::npos) ? line.substr(0, sep) : line;
            if (p == pkg) return true;
        }
    }

    std::ifstream custom(DATADIR "/umount_list");
    if (custom.is_open()) {
        std::string line;
        while (std::getline(custom, line)) {
            if (line.empty() || line[0] == '#') continue;
            if (line == pkg) return true;
        }
    }
    return false;
}

// ─── Companion handler ─────────────────────────────────────────────────
static void companionHandler(int client_fd) {
    uint32_t len = 0;
    if (read(client_fd, &len, sizeof(len)) != sizeof(len) || len == 0 || len > 512) {
        uint8_t resp = 0; write(client_fd, &resp, 1); return;
    }

    std::string pkgName(len, '\0');
    if (read(client_fd, &pkgName[0], len) != (ssize_t)len) {
        uint8_t resp = 0; write(client_fd, &resp, 1); return;
    }

    bool in_denylist = isInDenyList(pkgName);
    std::string app_mode = getAppMode(pkgName);

    uint8_t action = 0;
    if (in_denylist) {
        if (app_mode.find("persistent") != std::string::npos) action = 3;
        else if (app_mode.find("aggressive") != std::string::npos) action = 2;
        else action = 1;
    }

    LOGI("Companion: [%s] denylist=%d app_mode=%s action=%d",
         pkgName.c_str(), in_denylist, app_mode.c_str(), action);

    write(client_fd, &action, 1);
}

// ─── Main module ───────────────────────────────────────────────────────
class QwennHide : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api = api; this->env = env;
        LOGI("QwennHide loaded (WebUI per-app config)");
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        hide_action = 0;
        unloaded = false;

        if (!args || !args->nice_name) {
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true; return;
        }

        const char *raw = env->GetStringUTFChars(args->nice_name, nullptr);
        if (!raw) {
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true; return;
        }

        std::string pkg(raw);
        env->ReleaseStringUTFChars(args->nice_name, raw);
        size_t colon = pkg.find(':');
        if (colon != std::string::npos) pkg = pkg.substr(0, colon);

        int fd = api->connectCompanion();
        if (fd < 0) {
            LOGW("Companion connect failed, unloading");
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true; return;
        }

        uint32_t plen = (uint32_t)pkg.size();
        write(fd, &plen, sizeof(plen));
        write(fd, pkg.c_str(), plen);

        uint8_t resp = 0;
        read(fd, &resp, 1);
        close(fd);

        hide_action = resp;

        if (hide_action > 0) {
            LOGI("Hiding [%s] action=%d", pkg.c_str(), hide_action);
            api->setOption(zygisk::FORCE_DENYLIST_UNMOUNT);
        } else {
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true;
        }
    }

    void postAppSpecialize([[maybe_unused]] const zygisk::AppSpecializeArgs *args) override {
        if (unloaded || hide_action == 0) return;

        if (hide_action >= 2) {
            LOGD("Full cleanup (action=%d)", hide_action);
            closeLeakedFds();
            manualUnmount();
            cleanNeoZygiskTraces();
        }

        if (hide_action == 3) {
            LOGI("Persistent: module stays resident (pid=%d)", getpid());
            return;
        }

        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        unloaded = true;
    }

    void preServerSpecialize([[maybe_unused]] zygisk::ServerSpecializeArgs *args) override {
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        unloaded = true;
    }

    void postServerSpecialize([[maybe_unused]] const zygisk::ServerSpecializeArgs *args) override {}

private:
    zygisk::Api *api = nullptr;
    JNIEnv *env = nullptr;
    uint8_t hide_action = 0;
    bool unloaded = false;
};

REGISTER_ZYGISK_MODULE(QwennHide)
REGISTER_ZYGISK_COMPANION(companionHandler)
