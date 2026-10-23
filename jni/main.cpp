// QwennHide - main.cpp (NeoZygisk Aligned)
// Prinsip: NeoZygisk handle core mechanism, kita hanya tambah lapisan ekstra.

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

// ─── Paths yang BERSIH untuk di-unmount ─────────────────────────────────
// HANYA path Magisk yang jelas. TIDAK termasuk path NeoZygisk.
static const char *UNMOUNT_PATHS[] = {
    "/sbin/.magisk",
    "/data/adb/magisk",
    "/data/adb/modules",
    "/dev/.magisk",
    "/dev/.magisk.unblock",
    // ⚠️ JANGAN tambah:
    //   "/dev/zygisk"     → dipakai NeoZygisk
    //   "/dev/neozygisk"  → dipakai NeoZygisk
    //   "/data/adb/modules/neozygisk" → module dir NeoZygisk
    nullptr
};

// ─── FD paths untuk cleanup (Aggressive mode) ──────────────────────────
static const char *FD_CHECK_PATHS[] = {
    "/sbin/.magisk",
    "/data/adb/magisk",
    "/data/adb/modules",
    "/system/bin/su",
    "/system/xbin/su",
    "/sbin/su",
    nullptr
};

// ─── Utility: Close FD yang bocor ──────────────────────────────────────
static void closeLeakedFds() {
    DIR *fd_dir = opendir("/proc/self/fd");
    if (!fd_dir) return;

    struct dirent *entry;
    while ((entry = readdir(fd_dir)) != nullptr) {
        if (entry->d_name[0] == '.') continue;
        int fd = atoi(entry->d_name);
        if (fd <= 2) continue; // stdin/stdout/stderr

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

// ─── Utility: Unmount manual (fallback jika FORCE_DENYLIST tidak cukup) ─
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
            if (mountpoint.find(UNMOUNT_PATHS[i]) == 0) {
                should_unmount = true;
                break;
            }
        }

        // SAFETY: Jangan unmount path NeoZygisk/ZygiskNext
        if (mountpoint.find("/dev/zygisk") == 0 ||
            mountpoint.find("/dev/neozygisk") == 0 ||
            mountpoint.find("/dev/zygisksu") == 0 ||
            mountpoint.find("/data/adb/modules/neozygisk") == 0 ||
            mountpoint.find("/data/adb/modules/zygisksu") == 0) {
            should_unmount = false;
        }

        if (should_unmount) {
            to_unmount.push_back({mount_id, mountpoint});
        }
    }
    mi.close();

    // Unmount dari child ke parent
    for (auto it = to_unmount.rbegin(); it != to_unmount.rend(); ++it) {
        if (umount2(it->second.c_str(), MNT_DETACH) == 0) {
            LOGD("Manual unmount: %s", it->second.c_str());
        }
    }
}

// ─── Helper: Cek DenyList (multi-sumber, NeoZygisk-aware) ──────────────
static bool isInDenyList(const std::string &pkg) {
    // Sumber 1: Magisk CLI (jika Magisk Alpha terinstall bareng NeoZygisk)
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

    // Sumber 2: File denylist NeoZygisk (jika ada)
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

    // Sumber 3: Custom list milik QwennHide
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

// ─── Companion Handler (jalan di konteks root via NeoZygisk) ───────────
static void companionHandler(int client_fd) {
    uint32_t len = 0;
    if (read(client_fd, &len, sizeof(len)) != sizeof(len) || len == 0 || len > 512) {
        uint8_t resp = 0;
        write(client_fd, &resp, 1);
        return;
    }

    std::string pkgName(len, '\0');
    read(client_fd, &pkgName[0], len);

    // Baca mode (aman di konteks root)
    std::string mode = "basic";
    std::ifstream mf(MODE_FILE);
    if (mf.is_open()) std::getline(mf, mode);
    bool is_aggressive = (mode.find("aggressive") != std::string::npos);

    bool in_denylist = isInDenyList(pkgName);

    // 0 = skip, 1 = basic hide, 2 = aggressive hide
    uint8_t action = 0;
    if (in_denylist) {
        action = is_aggressive ? 2 : 1;
    }

    LOGI("Companion: [%s] denylist=%d mode=%s action=%d",
         pkgName.c_str(), in_denylist, mode.c_str(), action);

    write(client_fd, &action, 1);
}

// ─── Main Module ────────────────────────────────────────────────────────
class QwennHide : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api = api;
        this->env = env;
        LOGI("QwennHide loaded (NeoZygisk aligned)");
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        hide_action = 0;
        unloaded = false;

        if (!args->nice_name) {
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true;
            return;
        }

        const char *raw = env->GetStringUTFChars(args->nice_name, nullptr);
        if (!raw) {
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true;
            return;
        }

        std::string pkg(raw);
        env->ReleaseStringUTFChars(args->nice_name, raw);
        size_t colon = pkg.find(':');
        if (colon != std::string::npos) pkg = pkg.substr(0, colon);

        // Tanya companion (NeoZygisk yang manage lifecycle-nya)
        int fd = api->connectCompanion();
        if (fd < 0) {
            LOGW("Companion connect failed, unloading");
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true;
            return;
        }

        uint32_t len = (uint32_t)pkg.size();
        write(fd, &len, sizeof(len));
        write(fd, pkg.c_str(), len);

        uint8_t resp = 0;
        read(fd, &resp, 1);
        close(fd);

        hide_action = resp;

        if (hide_action > 0) {
            LOGI("Hiding [%s] action=%d", pkg.c_str(), hide_action);
            // Trigger NeoZygisk/Magisk untuk unmount overlay.
            // Ini adalah mekanisme RESMI, bukan hack.
            // Di NeoZygisk: mungkin no-op, tapi aman dipanggil.
            // Di Magisk Alpha: melakukan unmount sebenarnya.
            api->setOption(zygisk::FORCE_DENYLIST_UNMOUNT);
        } else {
            // Bukan target → unload segera, jangan tinggalkan jejak
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true;
        }
    }

    void postAppSpecialize([[maybe_unused]] const zygisk::AppSpecializeArgs *args) override {
        // Jika sudah unload di preAppSpecialize, tidak perlu lakukan apa-apa
        if (unloaded || hide_action == 0) return;

        if (hide_action == 2) {
            // Aggressive: tambahan cleanup yang NeoZygisk tidak lakukan
            LOGD("Aggressive: extra FD + mount cleanup");
            closeLeakedFds();
            manualUnmount();
        }

        // Unload module → tidak ada jejak di /proc/self/maps
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        unloaded = true;
    }

    void preServerSpecialize([[maybe_unused]] zygisk::ServerSpecializeArgs *args) override {
        // System server: selalu unload, jangan ganggu
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        unloaded = true;
    }

private:
    zygisk::Api *api = nullptr;
    JNIEnv *env = nullptr;
    uint8_t hide_action = 0;
    bool unloaded = false;
};

REGISTER_ZYGISK_MODULE(QwennHide)
REGISTER_ZYGISK_COMPANION(companionHandler)
