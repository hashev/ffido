/* Isolated SMAPI writer for verify-netmail.py; never opens production bases. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <smapi/msgapi.h>

static byte *read_file(const char *path, dword *size) {
    FILE *file = fopen(path, "rb");
    if (!file || fseek(file, 0, SEEK_END)) exit(10);
    long length = ftell(file);
    if (length < 0 || length > 65536 || fseek(file, 0, SEEK_SET)) exit(11);
    byte *data = calloc((size_t)length + 1, 1);
    if (!data || fread(data, 1, (size_t)length, file) != (size_t)length) exit(12);
    fclose(file);
    *size = (dword)length;
    return data;
}

int main(int argc, char **argv) {
    if (argc != 7) return 2;
    struct _minf info = {0};
    info.req_version = 2;
    info.def_zone = 2;
    if (MsgOpenApi(&info)) return 3;
    HAREA area = MsgOpenArea((byte *)argv[1], MSGAREA_NORMAL, MSGTYPE_JAM);
    if (!area) area = MsgOpenArea((byte *)argv[1], MSGAREA_CREATE, MSGTYPE_JAM);
    if (!area) return 4;
    HMSG message = MsgOpenMsg(area, MOPEN_CREATE, 0);
    if (!message) return 5;
    XMSG header = {0};
    header.attr = MSGLOCAL | MSGPRIVATE;
    header.orig.zone = header.dest.zone = 2;
    header.orig.net = header.dest.net = 1;
    header.orig.node = 1;
    header.dest.node = 2;
    strcpy((char *)header.__ftsc_date, "31 Oct 26  18:00:00");
    byte *values[5];
    dword sizes[5];
    for (int i = 0; i < 5; ++i) values[i] = read_file(argv[i + 2], &sizes[i]);
    if (sizes[0] >= sizeof(header.from) || sizes[1] >= sizeof(header.to) ||
        sizes[2] >= sizeof(header.subj)) return 6;
    memcpy(header.from, values[0], sizes[0]);
    memcpy(header.to, values[1], sizes[1]);
    memcpy(header.subj, values[2], sizes[2]);
    if (MsgWriteMsg(message, 0, &header, values[3], sizes[3], sizes[3], sizes[4] + 1, values[4])) return 7;
    if (MsgCloseMsg(message) || MsgCloseArea(area) || MsgCloseApi()) return 8;
    for (int i = 0; i < 5; ++i) free(values[i]);
    return 0;
}
