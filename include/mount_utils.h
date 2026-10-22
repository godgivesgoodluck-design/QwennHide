#ifndef MOUNT_UTILS_H
#define MOUNT_UTILS_H

#include <string>
#include <vector>

namespace mount_utils {

struct MountInfo {
    int mount_id;
    int parent_id;
    std::string root;
    std::string mount_point;
    std::string fs_type;
    std::string mount_source;
};

extern const std::vector<std::string> ROOT_MOUNT_PATTERNS;
extern const std::vector<std::string> HIDE_FILE_PATHS;

std::vector<MountInfo> parse_mountinfo();
bool is_root_mount(const MountInfo& info);
int unmount_root_mounts();
int hide_files();
int setup_proc_filter();

} // namespace mount_utils

#endif // MOUNT_UTILS_H
