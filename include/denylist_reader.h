#ifndef DENYLIST_READER_H
#define DENYLIST_READER_H

#include <string>
#include <vector>
#include <unordered_set>
#include <mutex>

namespace denylist_reader {

class DenyListReader {
public:
    static DenyListReader& instance();
    
    bool load();
    bool reload();
    bool contains(const std::string& package_name) const;
    size_t size() const;
    std::vector<std::string> get_all_packages() const;
    bool is_loaded() const;
    
private:
    DenyListReader() = default;
    ~DenyListReader() = default;
    DenyListReader(const DenyListReader&) = delete;
    DenyListReader& operator=(const DenyListReader&) = delete;
    
    bool load_from_database();
    bool load_from_cli();
    bool load_from_text_file();
    
    std::vector<std::string> parse_cli_output(const std::string& output);
    std::vector<std::string> parse_text_file(const std::string& content);
    
    std::unordered_set<std::string> packages_;
    mutable std::mutex mutex_;
    bool loaded_ = false;
    std::string last_source_;
    long long last_load_time_ = 0;
    static constexpr long long REFRESH_INTERVAL_MS = 30000;
};

} // namespace denylist_reader

#endif // DENYLIST_READER_H
