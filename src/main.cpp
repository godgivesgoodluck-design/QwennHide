#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>

#include "zygisk.hpp"
#include "props.h"

#include <jni.h>
#include <string>

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

namespace {

// ---- Mode flag file ----
// Path ini ada di dalam folder module, bisa dibaca zygote
constexpr const char *MODE_FILE = "/data/adb/modules/qwennhide/mode";

enum class Mode { BASIC, AGGRESSIVE };

// Cache untuk menghindari baca file setiap kali
static Mode g_cached_mode = Mode::BASIC;
static time_t g_last_check = 0;
constexpr time_t CHECK_INTERVAL_SEC = 5;

Mode read_current_mode() {
    time_t now = time(nullptr);
    if ((now - g_last_check) < CHECK_INTERVAL_SEC) {
        return g_cached_mode;
    }
    
    int fd = open(MODE_FILE, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        // File belum ada (module baru diinstall, customize.sh belum jalan?)
        // Default ke basic
        g_cached_mode = Mode::BASIC;
        g_last_check = now;
        return g_cached_mode;
    }
    
    char buf[32] = {0};
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    
    if (n <= 0) {
        g_cached_mode = Mode::BASIC;
    } else {
        // Trim whitespace/newline
        for (ssize_t i = 0; i < n; i++) {
            if (buf[i] == '\n' || buf[i] == '\r' || buf[i] == ' ' || buf[i] == '\t') {
                buf[i] = '\0';
                break;
            }
        }
        if (strcmp(buf, "aggressive") == 0) {
            g_cached_mode = Mode::AGGRESSIVE;
        } else {
            g_cached_mode = Mode::BASIC;
        }
    }
    
    g_last_check = now;
    return g_cached_mode;
}

// ---- JNI helpers ----
std::string read_jstring(JNIEnv *env, jstring s) {
    if (env == nullptr || s == nullptr) return {};
    const char *c = env->GetStringUTFChars(s, nullptr);
    if (c == nullptr) return {};
    std::string out(c);
    env->ReleaseStringUTFChars(s, c);
    return out;
}

std::string package_name(zygisk::AppSpecializeArgs *args, JNIEnv *env) {
    std::string dir = read_jstring(env, args->app_data_dir);
    if (!dir.empty()) {
        auto slash = dir.find_last_of('/');
        if (slash != std::string::npos && slash + 1 < dir.size())
            return dir.substr(slash + 1);
    }
    std::string nice = read_jstring(env, args->nice_name);
    auto colon = nice.find(':');
    if (colon != std::string::npos) nice.resize(colon);
    return nice;
}

bool request_companion_unmount(int companion_fd, pid_t target_pid) {
    if (companion_fd < 0) return false;
    int cmd = static_cast<int>(qwennhide::Cmd::UNMOUNT_TARGET);
    if (write(companion_fd, &cmd, sizeof(cmd)) != sizeof(cmd)) return false;
    if (write(companion_fd, &target_pid, sizeof(target_pid)) != sizeof(target_pid)) return false;
    int ack = 0;
    if (read(companion_fd, &ack, sizeof(ack)) != sizeof(ack)) return false;
    return ack == 1;
}

// ---- Module class ----
class QwennHide : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        api_ = api;
        env_ = env;
        LOGI("QwennHide loaded. Mode file: %s", MODE_FILE);
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        target_ = false;
        aggressive_ = false;
        companion_fd_ = -1;

        if (args == nullptr || api_ == nullptr || env_ == nullptr) return;

        const std::string pkg = package_name(args, env_);
        if (pkg.empty()) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        const uint32_t flags = api_->getFlags();
        
        if ((flags & zygisk::PROCESS_ON_DENYLIST) == 0) {
            // Bukan target denylist -> unload module
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        target_ = true;
        
        // Baca mode dari file flag (dengan cache)
        Mode mode = read_current_mode();
        aggressive_ = (mode == Mode::AGGRESSIVE);
        
        LOGI("pkg=%s mode=%s", pkg.c_str(), 
             aggressive_ ? "AGGRESSIVE" : "BASIC");

        // Minta host unmount (bekerja di Magisk, mungkin no-op di NeoZygisk)
        api_->setOption(zygisk::FORCE_DENYLIST_UNMOUNT);

        if (aggressive_) {
            // ===== MODE AGGRESSIVE =====
            // Hook aktif, companion aktif, module tetap di memory
            companion_fd_ = api_->connectCompanion();
            if (companion_fd_ < 0) {
                LOGE("companion connect failed");
            }

            // Register semua hook
            api_->pltHookRegister(0, 0, "__system_property_get",
                (void *)qwennhide::fake_system_property_get,
                (void **)&qwennhide::hooks::system_property_get);
            api_->pltHookRegister(0, 0, "stat",
                (void *)qwennhide::fake_stat,
                (void **)&qwennhide::hooks::stat_fn);
            api_->pltHookRegister(0, 0, "lstat",
                (void *)qwennhide::fake_lstat,
                (void **)&qwennhide::hooks::lstat_fn);
            api_->pltHookRegister(0, 0, "access",
                (void *)qwennhide::fake_access,
                (void **)&qwennhide::hooks::access_fn);
            api_->pltHookRegister(0, 0, "faccessat",
                (void *)qwennhide::fake_faccessat,
                (void **)&qwennhide::hooks::faccessat_fn);
            api_->pltHookRegister(0, 0, "open",
                (void *)qwennhide::fake_open,
                (void **)&qwennhide::hooks::open_fn);
            api_->pltHookRegister(0, 0, "openat",
                (void *)qwennhide::fake_openat,
                (void **)&qwennhide::hooks::openat_fn);
            api_->pltHookRegister(0, 0, "readlink",
                (void *)qwennhide::fake_readlink,
                (void **)&qwennhide::hooks::readlink_fn);
            api_->pltHookRegister(0, 0, "fopen",
                (void *)qwennhide::fake_fopen,
                (void **)&qwennhide::hooks::fopen_fn);

            if (!api_->pltHookCommit()) {
                LOGE("pltHookCommit failed");
            } else {
                LOGI("aggressive hooks committed");
            }
            // JANGAN unload module (hook harus resident)
        } else {
            // ===== MODE BASIC =====
            // Unload module agar tidak terdeteksi di /proc/self/maps
            // Hanya mengandalkan FORCE_DENYLIST_UNMOUNT dari host
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        }
    }

    void postAppSpecialize([[maybe_unused]] const zygisk::AppSpecializeArgs *args) override {
        if (!target_) return;
        if (!aggressive_) return; // Mode basic sudah unload di pre

        if (companion_fd_ >= 0) {
            pid_t self = getpid();
            if (request_companion_unmount(companion_fd_, self)) {
                LOGI("companion unmount OK pid=%d", self);
            } else {
                LOGE("companion unmount FAILED pid=%d", self);
            }
            close(companion_fd_);
            companion_fd_ = -1;
        }
    }

private:
    zygisk::Api *api_ = nullptr;
    JNIEnv *env_ = nullptr;
    bool target_ = false;
    bool aggressive_ = false;
    int companion_fd_ = -1;
};

} // namespace

REGISTER_ZYGISK_MODULE(QwennHide)
REGISTER_ZYGISK_COMPANION(qwennhide_companion_entry)
