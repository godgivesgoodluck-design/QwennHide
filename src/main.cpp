#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

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

class QwennHide : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        api_ = api;
        env_ = env;
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        target_ = false;
        companion_fd_ = -1;

        if (args == nullptr || api_ == nullptr || env_ == nullptr) return;

        const std::string pkg = package_name(args, env_);
        if (pkg.empty()) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        const uint32_t flags = api_->getFlags();
        LOGI("pkg=%s flags=0x%x", pkg.c_str(), flags);

        if ((flags & zygisk::PROCESS_ON_DENYLIST) == 0) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        target_ = true;

        api_->setOption(zygisk::FORCE_DENYLIST_UNMOUNT);

        companion_fd_ = api_->connectCompanion();
        if (companion_fd_ < 0) {
            LOGE("companion connect failed");
        }

        // ⭐ PERBAIKAN: Gunakan qwennhide::fake_* dan qwennhide::hooks::*
        api_->pltHookRegister(0, 0, "__system_property_get",
                              (void *)qwennhide::fake_system_property_get,
                              (void **)&qwennhide::hooks::system_property_get);
        api_->pltHookRegister(0, 0, "stat",
                              (void *)qwennhide::fake_stat,
                              (void **)&qwennhide::hooks::stat_fn);
        api_->pltHookRegister(0, 0, "access",
                              (void *)qwennhide::fake_access,
                              (void **)&qwennhide::hooks::access_fn);
        api_->pltHookRegister(0, 0, "fopen",
                              (void *)qwennhide::fake_fopen,
                              (void **)&qwennhide::hooks::fopen_fn);

        if (!api_->pltHookCommit()) {
            LOGE("pltHookCommit failed");
        } else {
            LOGI("hooks committed");
        }
    }

    // ⭐ PERBAIKAN: Tambahkan [[maybe_unused]] untuk args
    void postAppSpecialize([[maybe_unused]] const zygisk::AppSpecializeArgs *args) override {
        if (!target_) return;

        if (companion_fd_ >= 0) {
            pid_t self = getpid();
            if (request_companion_unmount(companion_fd_, self)) {
                LOGI("companion unmount OK for pid %d", self);
            } else {
                LOGE("companion unmount FAILED for pid %d", self);
            }
            close(companion_fd_);
            companion_fd_ = -1;
        }
    }

private:
    zygisk::Api *api_ = nullptr;
    JNIEnv *env_ = nullptr;
    bool target_ = false;
    int companion_fd_ = -1;
};

} // namespace

REGISTER_ZYGISK_MODULE(QwennHide)
REGISTER_ZYGISK_COMPANION(qwennhide_companion_entry)
