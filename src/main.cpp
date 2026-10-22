#include "zygisk.hpp"
#include "mount_utils.h"
#include "proc_filter.h"
#include "denylist_reader.h"
#include <string>
#include <vector>
#include <unistd.h>
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
        
        LOGI("MyRootHider module loaded (Magisk Alpha + NeoZygisk optimized)");
        
        auto& reader = denylist_reader::DenyListReader::instance();
        if (reader.load()) {
            LOGI("DenyList loaded successfully: %zu packages", reader.size());
        } else {
            LOGE("Failed to load DenyList from Magisk");
        }
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
        
        if (package_name.empty()) {
            return;
        }
        
        auto& reader = denylist_reader::DenyListReader::instance();
        
        if (!reader.is_loaded()) {
            reader.load();
        }
        
        if (reader.contains(package_name)) {
            LOGI("App %s is in Magisk DenyList - will hide root", 
                 package_name.c_str());
            should_hide = true;
            
            // Request built-in denylist unmount (optional, untuk kompatibilitas)
            api->setOption(zygisk::OPTION_DENYLIST);
        } else {
            should_hide = false;
            LOGD("App %s not in DenyList, skipping", package_name.c_str());
        }
    }

    void postAppSpecialize(const zygisk::AppSpecializeArgs *args) override {
        if (!should_hide) {
            return;
        }
        
        LOGI("=== Performing root hide in app namespace ===");
        
        LOGI("[1/4] Filtering procfs...");
        mount_utils::setup_proc_filter();
        
        LOGI("[2/4] Unmounting root mounts...");
        mount_utils::unmount_root_mounts();
        
        LOGI("[3/4] Hiding sensitive files...");
        mount_utils::hide_files();
        
        LOGI("[4/4] Root hiding completed!");
        
        LOGI("Unloading module from memory...");
        api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }

private:
    zygisk::Api *api;
    JNIEnv *env;
    bool should_hide = false;
};

REGISTER_ZYGISK_MODULE(MyRootHiderModule)
