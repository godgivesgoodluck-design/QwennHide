#include <sys/types.h>
#include "zygisk.hpp"
#include "mount_utils.h"
#include "proc_filter.h"
#include <string>
#include <android/log.h>

#define LOG_TAG "MyRootHider"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

class MyRootHiderModule : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api = api;
        this->env = env;
        LOGI("MyRootHider module loaded");
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        std::string package_name;
        if (args->nice_name != nullptr) {
            const char *name = env->GetStringUTFChars(args->nice_name, nullptr);
            if (name) {
                package_name = name;
                env->ReleaseStringUTFChars(args->nice_name, name);
            }
        }
        
        if (package_name.empty()) return;
        
        // CARA NATIVE: Cek apakah aplikasi ada di DenyList Magisk/NeoZygisk
        uint32_t flags = api->getFlags();
        if (flags & zygisk::PROCESS_ON_DENYLIST) {
            LOGI("App %s is on DenyList. Will hide root.", package_name.c_str());
            should_hide = true;
            
            // Minta host (Magisk/NeoZygisk) untuk melakukan unmount bawaan
            api->setOption(zygisk::FORCE_DENYLIST_UNMOUNT);
        } else {
            should_hide = false;
            LOGD("App %s not on DenyList, skipping.", package_name.c_str());
        }
    }

    void postAppSpecialize(const zygisk::AppSpecializeArgs *args) override {
        if (!should_hide) return;
        
        LOGI("Performing root hide in app namespace...");
        
        mount_utils::setup_proc_filter();
        mount_utils::unmount_root_mounts();
        mount_utils::hide_files();
        
        LOGI("Root hiding completed. Unloading module...");
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

private:
    zygisk::Api *api;
    JNIEnv *env;
    bool should_hide = false;
};

REGISTER_ZYGISK_MODULE(MyRootHiderModule)
