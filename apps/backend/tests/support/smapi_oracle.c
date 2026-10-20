// Independent test executable: only Husky SMAPI headers/library, never FFIDO's JAM codec.
#include <fcntl.h>
#include <limits.h>
// SMAPI requires msgapi.h before api_jam.h.
// clang-format off
#include <smapi/msgapi.h>
#include <smapi/api_jam.h>
// clang-format on
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int raw_header(const char *base, unsigned long slot, JAMHDR *header) {
  char path[4096];
  if (snprintf(path, sizeof(path), "%s.jdx", base) >= (int)sizeof(path))
    return 0;
  int fd = open(path, O_RDONLY);
  if (fd < 0)
    return 0;
  JAMIDXREC index;
  int ok = lseek(fd, (off_t)(slot - 1) * 8, SEEK_SET) >= 0 && read_idx(fd, &index) == 1;
  close(fd);
  if (!ok || index.HdrOffset == 0xffffffffu)
    return 0;
  if (snprintf(path, sizeof(path), "%s.jhr", base) >= (int)sizeof(path))
    return 0;
  fd = open(path, O_RDONLY);
  if (fd < 0)
    return 0;
  ok = lseek(fd, index.HdrOffset, SEEK_SET) >= 0 && read_hdr(fd, header) == 1;
  close(fd);
  return ok;
}

static void constants(void) {
#define FLAG(name, value) printf("\"" name "\":%lu,", (unsigned long)(value))
  printf("{");
  FLAG("Local", JMSG_LOCAL);
  FLAG("InTransit", JMSG_INTRANSIT);
  FLAG("Private", JMSG_PRIVATE);
  FLAG("Read", JMSG_READ);
  FLAG("Sent", JMSG_SENT);
  FLAG("KillSent", JMSG_KILLSENT);
  FLAG("ArchiveSent", JMSG_ARCHIVESENT);
  FLAG("Hold", JMSG_HOLD);
  FLAG("Crash", JMSG_CRASH);
  FLAG("Immediate", JMSG_IMMEDIATE);
  FLAG("Direct", JMSG_DIRECT);
  FLAG("Gate", JMSG_GATE);
  FLAG("FileRequest", JMSG_FILEREQUEST);
  FLAG("FileAttached", JMSG_FILEATTACH);
  FLAG("TruncFile", JMSG_TRUNCFILE);
  FLAG("KillFile", JMSG_KILLFILE);
  FLAG("ReceiptRequest", JMSG_RECEIPTREQ);
  FLAG("ConfirmRequest", JMSG_CONFIRMREQ);
  FLAG("Orphan", JMSG_ORPHAN);
  FLAG("Encrypted", JMSG_ENCRYPT);
  FLAG("Compressed", JMSG_COMPRESS);
  FLAG("Escaped", JMSG_ESCAPED);
  FLAG("Fpu", JMSG_FPU);
  FLAG("TypeLocal", JMSG_TYPELOCAL);
  FLAG("TypeEcho", JMSG_TYPEECHO);
  FLAG("TypeNet", JMSG_TYPENET);
  FLAG("NoDisplay", JMSG_NODISP);
  FLAG("Locked", JMSG_LOCKED);
  printf("\"Deleted\":%lu}\n", (unsigned long)JMSG_DELETED);
#undef FLAG
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "constants") == 0) {
    constants();
    return 0;
  }
  if (argc != 4 || (strcmp(argv[1], "read") != 0 && strcmp(argv[1], "incoming") != 0))
    return 2;
  char *end;
  unsigned long slot = strtoul(argv[3], &end, 10);
  if (!*argv[3] || *end || slot == 0 || slot > UINT_MAX)
    return 2;
  struct _minf info = {0};
  info.req_version = 2;
  info.def_zone = 2;
  if (MsgOpenApi(&info) != 0)
    return 3;
  HAREA area = MsgOpenArea((byte *)argv[2], MSGAREA_NORMAL, MSGTYPE_JAM);
  if (!area) {
    MsgCloseApi();
    return 4;
  }
  int result = 0;
  if (strcmp(argv[1], "incoming") == 0) {
    HMSG message = MsgOpenMsg(area, MOPEN_CREATE, 0);
    if (!message)
      result = 5;
    else {
      XMSG header = {0};
      header.attr = MSGPRIVATE;
      header.orig.zone = 2;
      header.orig.net = 1;
      header.orig.node = 3;
      header.orig.point = 4;
      header.dest.zone = 2;
      header.dest.net = 1;
      header.dest.node = 2;
      header.dest.point = 1;
      strcpy((char *)header.from, "Remote");
      strcpy((char *)header.to, "Owner");
      strcpy((char *)header.subj, "Incoming from SMAPI");
      byte body[] = "Independent incoming\r";
      byte control[] = "\1MSGID: 2:1/3.4 1234abcd\1CHRS: CP866 2";
      if (MsgWriteMsg(message, 0, &header, body, sizeof(body) - 1, sizeof(body) - 1, sizeof(control), control) != 0)
        result = 6;
      if (MsgCloseMsg(message) != 0)
        result = 7;
    }
  } else {
    JAMHDR raw;
    HMSG message = MsgOpenMsg(area, MOPEN_READ, (dword)slot);
    XMSG header = {0};
    if (!message || !raw_header(argv[2], slot, &raw))
      result = 8;
    else if (MsgReadMsg(message, &header, 0, 0, NULL, 0, NULL) == (dword)-1)
      result = 9;
    else {
      printf("{\"wire_attributes\":%lu,\"local\":%s,\"private\":%s,\"sent\":%s,\"locked\":%s,"
             "\"origin\":\"%u:%u/%u.%u\",\"destination\":\"%u:%u/%u.%u\"}\n",
             (unsigned long)raw.Attribute, (header.attr & MSGLOCAL) ? "true" : "false",
             (header.attr & MSGPRIVATE) ? "true" : "false", (header.attr & MSGSENT) ? "true" : "false",
             (header.attr & MSGLOCKED) ? "true" : "false", header.orig.zone, header.orig.net, header.orig.node,
             header.orig.point, header.dest.zone, header.dest.net, header.dest.node, header.dest.point);
    }
    if (message && MsgCloseMsg(message) != 0)
      result = 10;
  }
  if (MsgCloseArea(area) != 0)
    result = 11;
  if (MsgCloseApi() != 0)
    result = 12;
  return result;
}
