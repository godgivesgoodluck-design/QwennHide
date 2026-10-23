// ═══════════════════════════════════════════════════════════════════════
// QwennHide — jni/main.cpp (FINAL)
// NeoZygisk Aligned Root Hider
//
// Arsitektur:
//   - Companion IPC untuk cek DenyList (multi-sumber)
//   - FORCE_DENYLIST_UNMOUNT sebagai trigger host unmount
//   - Mode Basic:  hanya host unmount + DLCLOSE
//   - Mode Aggressive: host unmount + FD cleanup + manual unmount
//                      + NeoZygisk trace cleanup + DLCLOSE
//
// Prinsip:
//   - Tidak ada PLT hook (hindari integrity check)
//   - Tidak ada property spoofing di C++ (ada di service.sh)
//   - Tidak baca file mode di app context (hanya di companion/root)
//   - DLCLOSE dipanggil maksimal 1x per app lifecycle
//   - System server selalu unload
//   - Tidak mengganggu daemon NeoZygisk
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

// ═══════════════════════════════════════════════════════════════════════
// PATH DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════

// Path Magisk/SU untuk FD cleanup (Aggressive)
static const char *FD_CHECK_PATHS[] = {
    "/sbin/.magisk",
    "/data/adb/magisk",
    "/data/adb/modules",
    "/system/bin/su",
    "/system/xbin/su",
    "/sbin/su",
    "/system/bin/.ext/.su",
    nullptr
};

// Path Magisk untuk manual unmount (Aggressive)
// TIDAK termasuk path NeoZygisk agar tidak mengganggu host
static const char *UNMOUNT_PATHS[] = {
    "/sbin/.magisk",
    "/data/adb/magisk",
    "/data/adb/modules",
    "/dev/.magisk",
    "/dev/.magisk.unblock",
    nullptr
};

// Path NeoZygisk untuk cleanup terpisah (Aggressive, setelah semua ops selesai)
static const char *NEOZYGISK_CLEANUP_PATHS[] = {
    "/dev/zygisk",
    "/dev/neozygisk",
    "/dev/zygisksu",
    nullptr
};

// ═══════════════════════════════════════════════════════════════════════
// UTILITY: Close leaked file descriptors (Magisk/SU)
// ═══════════════════════════════════════════════════════════════════════

static void closeLeakedFds() {
    DIR *fd_dir = opendir("/proc/self/fd");
    if (!fd_dir) return;

    struct dirent *entry;
    while ((entry = readdir(fd_dir)) != nullptr) {
        if (entry->d_name[0] == '.') continue;
        int fd = atoi(entry->d_name);
        if (fd <= 2) continue; // stdin, stdout, stderr

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

// ═══════════════════════════════════════════════════════════════════════
// UTILITY: Manual unmount Magisk paths (SKIP NeoZygisk paths)
// ═══════════════════════════════════════════════════════════════════════

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

        // SAFETY: Jangan unmount path NeoZygisk/ZygiskNext di sini.
        // NeoZygisk cleanup dilakukan terpisah di cleanNeoZygiskTraces()
        // setelah semua operasi module selesai.
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

    // Unmount dari child ke parent (reverse order)
    for (auto it = to_unmount.rbegin(); it != to_unmount.rend(); ++it) {
        if (umount2(it->second.c_str(), MNT_DETACH) == 0) {
            LOGD("Manual unmount: %s", it->second.c_str());
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// UTILITY: Clean NeoZygisk traces (Aggressive only, after all module ops)
// ═══════════════════════════════════════════════════════════════════════

static void cleanNeoZygiskTraces() {
    LOGD("Cleaning NeoZygisk traces from app namespace");

    // 1. Close FD yang mengarah ke path NeoZygisk
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
                    LOGD("Closed NeoZygisk fd %d -> %s", fd, target);
                    break;
                }
            }
        }
        closedir(fd_dir);
    }

    // 2. Unmount path NeoZygisk yang tersisa di app namespace
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

// ═══════════════════════════════════════════════════════════════════════
// DENYLIST CHECK (Multi-source: Magisk + NeoZygisk + Custom)
// ═══════════════════════════════════════════════════════════════════════

static bool isInDenyList(const std::string &pkg) {
    // Sumber 1: Magisk CLI (jika Magisk Alpha terinstall)
    FILE *pipe = popen("magisk --denylist ls 2>/dev/null", "r");
    if (pipe) {
        char buf[256];
        while (fgets(buf, sizeof(buf), pipe)) {
            std::string entry(buf);
            if (!entry.empty() && entry.back() == '\n') entry.pop_back();
            size_t sep = entry.find('|');
            std::string entry_pkg = (sep != std::string::npos) ? entry.substr(0, sep) : entry;
            if (entry_pkg == pkg) {
                pclose(pipe);
                return true;
            }
        }
        pclose(pipe);
    }

    // Sumber 2: File denylist NeoZygisk / ZygiskNext
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

    // Sumber 3: Custom umount_list milik QwennHide
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

// ═══════════════════════════════════════════════════════════════════════
// COMPANION HANDLER (jalan di konteks root, dikelola NeoZygisk)
// ═══════════════════════════════════════════════════════════════════════

static void companionHandler(int client_fd) {
    uint32_t len = 0;
    if (read(client_fd, &len, sizeof(len)) != sizeof(len) || len == 0 || len > 512) {
        uint8_t resp = 0;
        write(client_fd, &resp, 1);
        return;
    }

    std::string pkgName(len, '\0');
    if (read(client_fd, &pkgName[0], len) != (ssize_t)len) {
        uint8_t resp = 0;
        write(client_fd, &resp, 1);
        return;
    }

    // Baca mode (aman di konteks root, tidak kena SELinux)
    std::string mode = "basic";
    std::ifstream mf(MODE_FILE);
    if (mf.is_open()) std::getline(mf, mode);
    bool is_aggressive = (mode.find("aggressive") != std::string::npos);

    // Cek denylist multi-sumber
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

// ═══════════════════════════════════════════════════════════════════════
// MAIN MODULE CLASS
// ═══════════════════════════════════════════════════════════════════════

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

        if (!args || !args->nice_name) {
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

        // Strip ":process" suffix
        size_t colon = pkg.find(':');
        if (colon != std::string::npos) pkg = pkg.substr(0, colon);

        // Tanya companion (NeoZygisk yang manage lifecycle companion)
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

            // Trigger host unmount (Magisk atau NeoZygisk).
            // Best-effort: jika NeoZygisk tidak support, ini jadi no-op.
            // Fallback kita ada di manualUnmount() untuk mode Aggressive.
            api->setOption(zygisk::FORCE_DENYLIST_UNMOUNT);
        } else {
            // Bukan target → unload segera, jangan tinggalkan jejak
            api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            unloaded = true;
        }
    }

    void postAppSpecialize([[maybe_unused]] const zygisk::AppSpecializeArgs *args) override {
        // Guard: jika sudah unload di preAppSpecialize, skip
        if (unloaded || hide_action == 0) return;

        if (hide_action == 2) {
            // ─── AGGRESSIVE MODE ────────────────────────────────────────
            // Urutan penting:
            // 1. FD cleanup Magisk/SU
            // 2. Manual unmount Magisk (skip NeoZygisk)
            // 3. NeoZygisk trace cleanup (setelah semua ops selesai)
            LOGD("Aggressive: full cleanup sequence");
            closeLeakedFds();
            manualUnmount();
            cleanNeoZygiskTraces();
        }

        // Unload module → hilang dari /proc/self/maps
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        unloaded = true;
    }

    void preServerSpecialize([[maybe_unused]] zygisk::ServerSpecializeArgs *args) override {
        // System server: SELALU unload, jangan pernah ganggu
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        unloaded = true;
    }

    void postServerSpecialize([[maybe_unused]] const zygisk::ServerSpecializeArgs *args) override {
        // Tidak ada yang perlu dilakukan
    }

private:
    zygisk::Api *api = nullptr;
    JNIEnv *env = nullptr;
    uint8_t hide_action = 0;   // 0=skip, 1=basic, 2=aggressive
    bool unloaded = false;     // Guard agar DLCLOSE hanya 1x
};

REGISTER_ZYGISK_MODULE(QwennHide)
REGISTER_ZYGISK_COMPANION(companionHandler)
