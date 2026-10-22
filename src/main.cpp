#include <sys/types.h>
#include <sys/system_properties.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include "zygisk.hpp"
#include "mount_utils.h"
#include "proc_filter.h"
#include <string>
#include <android/log.h>

#define LOG_TAG "SysOverlayPatch"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Simpan pointer ke fungsi asli
static int (*orig_system_property_get)(const char *name, char *value) = nullptr;

// Fungsi palsu untuk memalsukan properti
static int fake_system_property_get(const char *name, char *value) {
    int len = orig_system_property_get(name, value);
    
    if (len > 0 && value != nullptr) {
        if (strcmp(name, "ro.build.tags") == 0) {
            strcpy(value, "release-keys");
            return strlen(value);
        }
        if (strcmp(name, "ro.debuggable") == 0) {
            strcpy(value, "0");
            return 1;
        }
        if (strcmp(name, "ro.secure") == 0) {
            strcpy(value, "1");
            return 1;
        }
        if (strcmp(name, "ro.build.type") == 0) {
            strcpy(value, "user");
            return strlen(value);
        }
        if (strcmp(name, "ro.kernel.android.rooted") == 0) {
            strcpy(value, "0");
            return 1;
        }
    }
    return len;
}

class MyRootHiderModule : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        this->api = api;
        this->env = env;
        LOGI("Module loaded");

        // Cari libc.so untuk melakukan PLT Hook
        FILE *fp = fopen("/proc/self/maps", "r");
        if (fp) {
            char line[512];
            dev_t libc_dev = 0;
            ino_t libc_inode = 0;
            
            while (fgets(line, sizeof(line), fp)) {
                if (strstr(line, "/system/lib") && strstr(line, "libc.so")) {
                    char perms[5], path[256];
                    unsigned long offset;
                    // Parse format: address perms offset dev inode pathname
                    if (sscanf(line, "%*x-%*x %4s %lx %x:%x %lu %255s", perms, &offset, 
                               (unsigned int*)&libc_dev, (unsigned int*)&libc_inode, path) == 5) {
                        break;
                    }
                }
            }
            fclose(fp);

            if (libc_dev != 0 && libc_inode != 0) {
                LOGI("Found libc.so: dev=%u, inode=%lu", libc_dev, libc_inode);
                
                // Register hook untuk __system_property_get
                api->pltHookRegister(libc_dev, libc_inode, "__system_property_get", 
                                     (void *)fake_system_property_get, 
                                     (void **)&orig_system_property_get);
                
                // Commit hook agar aktif
                if (api->pltHookCommit()) {
                    LOGI("Property spoofing hooks committed successfully");
                } else {
                    LOGE("Failed to commit PLT hooks");
                }
            }
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
        
        if (package_name.empty()) return;
        
        uint32_t flags = api->getFlags();
        if (flags & zygisk::PROCESS_ON_DENYLIST) {
            LOGI("App %s is on DenyList. Hiding root.", package_name.c_str());
            should_hide = true;
            
            // HAPUS baris FORCE_DENYLIST_UNMOUNT di sini agar module kita yang menangani 100%
            // api->setOption(zygisk::FORCE_DENYLIST_UNMOUNT); 
        } else {
            should_hide = false;
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
