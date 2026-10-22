#ifndef PROC_FILTER_H
#define PROC_FILTER_H

#include <string>

namespace proc_filter {

extern const char* FILTER_PATTERNS[];
extern const int FILTER_PATTERN_COUNT;

int create_filtered_file(const char* source_path, const char* dest_path);
int filter_mountinfo();
int filter_maps();
int filter_mounts();

} // namespace proc_filter

#endif // PROC_FILTER_H
