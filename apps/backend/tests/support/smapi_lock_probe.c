#include <smapi/msgapi.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
  if (argc != 3)
    return 2;
  struct _minf info = {0};
  info.req_version = MSGAPI_VERSION;
  info.def_zone = 2;
  if (MsgOpenApi(&info) != 0)
    return 3;
  fprintf(stderr, "SMAPI runtime=%u/0x%x date=%s haveshare=%u\n", info.smapi_version, info.smapi_subversion,
          smapi_cvs_date(), info.haveshare);
  if (!info.haveshare)
    return 4;
  HAREA area = MsgOpenArea((byte *)argv[2], MSGAREA_CRIFNEC, MSGTYPE_JAM | MSGTYPE_ECHO);
  if (!area)
    return 5;
  if (!strcmp(argv[1], "create")) {
    MsgCloseArea(area);
    MsgCloseApi();
    return 0;
  }
  if (!strcmp(argv[1], "cached-close")) {
    MsgSetHighWater(area, 1);
    printf("OPENED %lu\n", (unsigned long)MsgGetNumMsg(area));
    fflush(stdout);
    getchar();
    MsgCloseArea(area);
    MsgCloseApi();
    return 0;
  }
  int locked = MsgLock(area) == 0;
  if (!locked) {
    MsgCloseArea(area);
    MsgCloseApi();
    return 10;
  }
  puts("LOCKED");
  fflush(stdout);
  if (!strcmp(argv[1], "hold"))
    getchar();
  MsgUnlock(area);
  MsgCloseArea(area);
  MsgCloseApi();
  return 0;
}
