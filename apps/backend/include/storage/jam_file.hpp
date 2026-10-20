#pragma once
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>
#include <ios>
#include <limits>
#include <string>
#include <utility>

namespace msgapi {
// Positional I/O seam permits deterministic short-I/O and failure tests.
struct JamFileIo {
  virtual ~JamFileIo() = default;
  virtual ssize_t Read(int fd, void* bytes, size_t count, off_t offset) {
    return pread(fd, bytes, count, offset);
  }
  virtual ssize_t Write(int fd, const void* bytes, size_t count, off_t offset) {
    return pwrite(fd, bytes, count, offset);
  }
  virtual int Stat(int fd, struct stat* info) {
    return fstat(fd, info);
  }
  static JamFileIo& System() {
    static JamFileIo instance;
    return instance;
  }
};
// Positional I/O view: a borrowed descriptor is never duplicated or closed.
// The physical owner's lease must outlive every operation on a borrowed view.
class JamFile {
public:
  JamFile() = default;
  explicit JamFile(int borrowed, JamFileIo* io = nullptr)
      : fd_(borrowed), owned_(false), io_(io ? io : &JamFileIo::System()) {
  }
  ~JamFile() {
    close();
  }
  JamFile(const JamFile&) = delete;
  JamFile& operator=(const JamFile&) = delete;
  JamFile(JamFile&& other) noexcept {
    *this = std::move(other);
  }
  JamFile& operator=(JamFile&& other) noexcept {
    if (this != &other) {
      close();
      fd_ = std::exchange(other.fd_, -1);
      owned_ = other.owned_;
      read_offset_ = other.read_offset_;
      write_offset_ = other.write_offset_;
      failed_ = other.failed_;
      io_ = other.io_;
    }
    return *this;
  }
  void open(const std::string& path, std::ios::openmode) {
    close();
    owned_ = true;
    fd_ = ::open(path.c_str(), O_RDWR | O_CLOEXEC | O_NOFOLLOW);
    failed_ = fd_ < 0;
    read_offset_ = write_offset_ = 0;
  }
  void close() {
    if (owned_ && fd_ >= 0) {
      ::close(fd_);
    }
    fd_ = -1;
    failed_ = false;
    read_offset_ = write_offset_ = 0;
  }
  bool is_open() const {
    return fd_ >= 0;
  }
  bool fail() const {
    return failed_;
  }
  void clear() {
    failed_ = false;
  }
  void flush() {
  }  // pwrite has no userspace buffer; durability requires explicit fsync.
  void seekg(std::streamoff offset, std::ios::seekdir dir = std::ios::beg) {
    seek(read_offset_, offset, dir);
  }
  void seekp(std::streamoff offset, std::ios::seekdir dir = std::ios::beg) {
    seek(write_offset_, offset, dir);
  }
  std::streampos tellg() const {
    return failed_ ? std::streampos(-1) : std::streampos(read_offset_);
  }
  std::streampos tellp() const {
    return failed_ ? std::streampos(-1) : std::streampos(write_offset_);
  }
  void read(char* buffer, std::streamsize count) {
    if (failed_ || count < 0) {
      failed_ = true;
      return;
    }
    while (count > 0) {
      const auto got = io_->Read(fd_, buffer, static_cast<size_t>(count), read_offset_);
      if (got < 0 && errno == EINTR)
        continue;
      if (got <= 0) {
        failed_ = true;
        return;
      }
      read_offset_ += got;
      buffer += got;
      count -= got;
    }
  }
  void write(const char* buffer, std::streamsize count) {
    if (failed_ || count < 0) {
      failed_ = true;
      return;
    }
    while (count > 0) {
      const auto written = io_->Write(fd_, buffer, static_cast<size_t>(count), write_offset_);
      if (written < 0 && errno == EINTR)
        continue;
      if (written <= 0) {
        failed_ = true;
        return;
      }
      write_offset_ += written;
      buffer += written;
      count -= written;
    }
  }

private:
  void seek(off_t& position, std::streamoff offset, std::ios::seekdir dir) {
    if (failed_)
      return;
    off_t origin = 0;
    if (dir == std::ios::cur)
      origin = position;
    else if (dir == std::ios::end) {
      struct stat info{};
      if (io_->Stat(fd_, &info) != 0 || info.st_size < 0) {
        failed_ = true;
        return;
      }
      origin = info.st_size;
    } else if (dir != std::ios::beg) {
      failed_ = true;
      return;
    }
    if ((offset < 0 && offset < -origin) || (offset > 0 && offset > std::numeric_limits<off_t>::max() - origin)) {
      failed_ = true;
      return;
    }
    position = origin + offset;
  }
  int fd_ = -1;
  bool owned_ = true;
  JamFileIo* io_ = &JamFileIo::System();
  bool failed_ = false;
  off_t read_offset_ = 0, write_offset_ = 0;
};
}  // namespace msgapi
