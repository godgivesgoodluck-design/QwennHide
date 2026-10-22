#include "denylist_reader.h"
#include <fstream>
#include <sstream>
#include <cstdio>
#include <cstdlib>
#include <sys/stat.h>
#include <unistd.h>
#include <android/log.h>
#include <chrono>

#define LOG_TAG "MyRootHider"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace denylist_reader {

DenyListReader& DenyListReader::instance() {
    static DenyListReader instance;
    return instance;
}

bool DenyListReader::load() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();
    
    if (loaded_ && (now - last_load_time_) < REFRESH_INTERVAL_MS) {
        LOGD("DenyList still fresh, skipping reload");
        return true;
    }
    
    packages_.clear();
    last_source_ = "none";
    
    if (load_from_database()) {
        last_source_ = "database";
    } else if (load_from_cli()) {
        last_source_ = "cli";
    } else if (load_from_text_file()) {
        last_source_ = "text_file";
    } else {
        LOGE("Failed to load denylist from any source");
        return false;
    }
    
    loaded_ = true;
    last_load_time_ = now;
    
    LOGI("DenyList loaded from %s: %zu packages", 
         last_source_.c_str(), packages_.size());
    
    return true;
}

bool DenyListReader::reload() {
    std::lock_guard<std::mutex> lock(mutex_);
    last_load_time_ = 0;
    
    packages_.clear();
    last_source_ = "none";
    
    if (load_from_database()) {
        last_source_ = "database";
    } else if (load_from_cli()) {
        last_source_ = "cli";
    } else if (load_from_text_file()) {
        last_source_ = "text_file";
    } else {
        return false;
    }
    
    loaded_ = true;
    last_load_time_ = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();
    
    LOGI("DenyList reloaded from %s: %zu packages", 
         last_source_.c_str(), packages_.size());
    
    return true;
}

bool DenyListReader::contains(const std::string& package_name) const {
    std::lock_guard<std::mutex> lock(mutex_);
    return packages_.find(package_name) != packages_.end();
}

size_t DenyListReader::size() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return packages_.size();
}

std::vector<std::string> DenyListReader::get_all_packages() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return std::vector<std::string>(packages_.begin(), packages_.end());
}

bool DenyListReader::is_loaded() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return loaded_;
}

bool DenyListReader::load_from_database() {
    const std::vector<std::string> db_paths = {
        "/data/adb/magisk/denylist.db",
        "/data/adb/magisk/db.db",
        "/data/adb/magisk/magisk.db",
    };
    
    std::string db_path;
    for (const auto& path : db_paths) {
        struct stat st;
        if (stat(path.c_str(), &st) == 0) {
            db_path = path;
            break;
        }
    }
    
    if (db_path.empty()) {
        LOGD("DenyList database not found");
        return false;
    }
    
    std::string cmd = "sqlite3 '" + db_path + "' "
                      "\"SELECT package_name FROM denylist WHERE state = 1;\" 2>/dev/null";
    
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        LOGD("Failed to execute sqlite3 command");
        return false;
    }
    
    char buffer[256];
    std::string output;
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        output += buffer;
    }
    
    int status = pclose(pipe);
    if (status != 0) {
        LOGD("sqlite3 command failed with status %d", status);
        return false;
    }
    
    std::istringstream iss(output);
    std::string line;
    int count = 0;
    
    while (std::getline(iss, line)) {
        size_t start = line.find_first_not_of(" \t\r\n");
        size_t end = line.find_last_not_of(" \t\r\n");
        
        if (start == std::string::npos) continue;
        
        std::string pkg = line.substr(start, end - start + 1);
        
        if (pkg.find('.') != std::string::npos && !pkg.empty()) {
            packages_.insert(pkg);
            count++;
        }
    }
    
    LOGD("Loaded %d packages from database %s", count, db_path.c_str());
    return count > 0;
}

bool DenyListReader::load_from_cli() {
    const std::vector<std::string> magisk_paths = {
        "/data/adb/magisk/magisk",
        "/system/bin/magisk",
        "/sbin/magisk",
    };
    
    std::string magisk_bin;
    for (const auto& path : magisk_paths) {
        struct stat st;
        if (stat(path.c_str(), &st) == 0) {
            magisk_bin = path;
            break;
        }
    }
    
    if (magisk_bin.empty()) {
        magisk_bin = "magisk";
    }
    
    std::string cmd = magisk_bin + " --denylist ls 2>/dev/null";
    
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) {
        LOGD("Failed to execute magisk CLI");
        return false;
    }
    
    char buffer[512];
    std::string output;
    while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
        output += buffer;
    }
    
    int status = pclose(pipe);
    if (status != 0) {
        LOGD("magisk CLI failed with status %d", status);
        return false;
    }
    
    auto packages = parse_cli_output(output);
    for (const auto& pkg : packages) {
        packages_.insert(pkg);
    }
    
    LOGD("Loaded %zu packages from magisk CLI", packages.size());
    return !packages.empty();
}

bool DenyListReader::load_from_text_file() {
    const std::vector<std::string> file_paths = {
        "/data/adb/magisk/denylist",
        "/data/adb/magisk/denylist.txt",
    };
    
    std::string file_path;
    for (const auto& path : file_paths) {
        struct stat st;
        if (stat(path.c_str(), &st) == 0) {
            file_path = path;
            break;
        }
    }
    
    if (file_path.empty()) {
        LOGD("DenyList text file not found");
        return false;
    }
    
    std::ifstream file(file_path);
    if (!file.is_open()) {
        return false;
    }
    
    std::ostringstream ss;
    ss << file.rdbuf();
    std::string content = ss.str();
    
    auto packages = parse_text_file(content);
    for (const auto& pkg : packages) {
        packages_.insert(pkg);
    }
    
    LOGD("Loaded %zu packages from text file %s", packages.size(), file_path.c_str());
    return !packages.empty();
}

std::vector<std::string> DenyListReader::parse_cli_output(const std::string& output) {
    std::vector<std::string> packages;
    std::istringstream iss(output);
    std::string line;
    
    while (std::getline(iss, line)) {
        size_t start = line.find_first_not_of(" \t\r\n");
        size_t end = line.find_last_not_of(" \t\r\n");
        
        if (start == std::string::npos) continue;
        
        std::string pkg = line.substr(start, end - start + 1);
        
        size_t space_pos = pkg.find(' ');
        if (space_pos != std::string::npos) {
            pkg = pkg.substr(0, space_pos);
        }
        
        if (pkg.find('.') != std::string::npos && !pkg.empty()) {
            packages.push_back(pkg);
        }
    }
    
    return packages;
}

std::vector<std::string> DenyListReader::parse_text_file(const std::string& content) {
    std::vector<std::string> packages;
    std::istringstream iss(content);
    std::string line;
    
    while (std::getline(iss, line)) {
        size_t start = line.find_first_not_of(" \t\r\n");
        size_t end = line.find_last_not_of(" \t\r\n");
        
        if (start == std::string::npos) continue;
        
        std::string pkg = line.substr(start, end - start + 1);
        
        if (pkg[0] == '#') continue;
        
        if (pkg.find('.') != std::string::npos) {
            packages.push_back(pkg);
        }
    }
    
    return packages;
}

} // namespace denylist_reader
