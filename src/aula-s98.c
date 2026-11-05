// aula-s98 — native macOS lighting control for the AULA S98 Pro (SONiX 0c45:800A)
// Speaks the keyboard's own vendor HID protocol, recovered from the Windows driver.
// Transport: 64-byte HID Feature report, report ID 0, on the 0xFF13 vendor collection.
// Build: clang -O2 -framework IOKit -framework CoreFoundation -o aula-s98 aula-s98.c

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <math.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>

#define VID    0x0C45
#define PID    0x800A
#define UPAGE  0xFF13      /* vendor collection carrying the 64-byte Feature report */
#define PKT    64
#define DELAY  35000       /* cmd_delaytime=35ms, from the driver's rgb-keyboard.xml */

static int verbose = 0;

struct Mode { int id; const char *name; int animated; int uses_color; };
/* Mode id, name, animated, uses the chosen colour.
 *
 * The nine names AULA's own driver provides are exact. The rest come from the
 * printed manual's twenty-effect list; the LCD effect number for each mode was
 * recorded by hand on the hardware (see data/mode-labels.json) and the manual's
 * two-column ordering was pinned down by the fact that those eleven numbers plus
 * the nine named modes must partition 1..20 exactly once. */
static const struct Mode kModes[] = {
    {0,  "Off",                           0, 0},
    {1,  "Static On",                     0, 1},
    {2,  "Single light up",               1, 1},
    {3,  "Single extinction",             1, 1},
    {4,  "Starlight",                     1, 1},
    {5,  "Fluttering",                    1, 1},
    {6,  "Flowers are blooming",          1, 1},
    {7,  "Dynamic Breathing",             1, 1},
    {8,  "Spectral cycle",                1, 1},
    {9,  "Colorful Fountain",             1, 0},
    {10, "Rainbow Wave",                  1, 0},
    {11, "Following Currents",            1, 1},
    {12, "Peak Revolving",                1, 1},
    {13, "Be touch-and-go",               1, 1},
    {14, "Kill two birds with one stone", 1, 1},
    {15, "Ripple diffusion",              1, 1},
    {16, "A continuous flow",             1, 1},
    {17, "Range upon range of mountains", 1, 1},
    {18, "Light wind and drizzling rain", 1, 1},
    {19, "Shuttle back and forth",        1, 1},
};
static const int kNumModes = (int)(sizeof(kModes) / sizeof(kModes[0]));

static const char *mode_name(int id) {
    for (int i = 0; i < kNumModes; i++) if (kModes[i].id == id) return kModes[i].name;
    return "(unnamed mode)";
}

/* Accept either a number or a case-insensitive name prefix. */
static int parse_mode(const char *a) {
    if (!a[0]) return -1;
    char *end = NULL;
    errno = 0;
    long n = strtol(a, &end, 0);
    /* Reject overflow and out-of-range before narrowing: without this, a value like
       4294967298 wraps to 2 and sails past the 0..19 check further down. */
    if (end && *end == 0 && end != a) {
        if (errno == ERANGE || n < 0 || n > 19) return -1;
        return (int)n;
    }
    for (int i = 0; i < kNumModes; i++)          /* case-insensitive substring */
        if (strcasestr(kModes[i].name, a)) return kModes[i].id;
    return -1;
}

static void put_num(CFMutableDictionaryRef d, const CFStringRef key, int v) {
    CFNumberRef n = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &v);
    CFDictionarySetValue(d, key, n);
    CFRelease(n);
}

static IOHIDDeviceRef find_device(IOHIDManagerRef mgr) {
    CFMutableDictionaryRef m = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    put_num(m, CFSTR(kIOHIDVendorIDKey), VID);
    put_num(m, CFSTR(kIOHIDProductIDKey), PID);
    put_num(m, CFSTR(kIOHIDPrimaryUsagePageKey), UPAGE);
    IOHIDManagerSetDeviceMatching(mgr, m);
    CFRelease(m);

    if (IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone) != kIOReturnSuccess) return NULL;
    CFSetRef set = IOHIDManagerCopyDevices(mgr);
    if (!set) return NULL;
    CFIndex n = CFSetGetCount(set);
    if (n == 0) { CFRelease(set); return NULL; }
    IOHIDDeviceRef *devs = calloc((size_t)n, sizeof(*devs));
    if (!devs) { CFRelease(set); return NULL; }
    CFSetGetValues(set, (const void **)devs);
    IOHIDDeviceRef dev = devs[0];
    CFRetain(dev);
    free(devs);
    CFRelease(set);
    return dev;
}

/* App and CLI share one firmware command state machine. Hold this advisory lock
   for the complete CLI operation so BEGIN/SELECT/payload/END replies cannot be
   consumed by the other process. */
static int acquire_process_lock(void) {
    char path[128];
    snprintf(path, sizeof path, "/tmp/io.github.lawsinex.aula-s98-pro-companion.%u.lock", (unsigned)getuid());
    int fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR);
    if (fd < 0) {
        fprintf(stderr, "error: could not open device lock: %s\n", strerror(errno));
        return -1;
    }
    struct stat info;
    if (fstat(fd, &info) || info.st_uid != getuid() || !S_ISREG(info.st_mode)) {
        fprintf(stderr, "error: unsafe device lock file\n");
        close(fd);
        return -1;
    }
    if (flock(fd, LOCK_EX | LOCK_NB)) {
        fprintf(stderr, "error: keyboard is busy in another Aula S98 Pro Companion process\n");
        close(fd);
        return -1;
    }
    return fd;
}

static int send_pkt(IOHIDDeviceRef dev, const uint8_t *buf, const char *label, int want_ack) {
    IOReturn r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 0, buf, PKT);
    if (r != kIOReturnSuccess) {
        fprintf(stderr, "error: SetReport(%s) failed: 0x%08x\n", label, r);
        return -1;
    }
    usleep(DELAY);

    /* The firmware only advances its command state machine once the host reads
       the reply back as a Feature report (the Windows driver does the same via
       IOCTL_HID_GET_FEATURE). Skipping this read makes the device ignore
       everything, silently. */
    uint8_t reply[PKT];
    CFIndex len = PKT;
    memset(reply, 0, PKT);
    IOReturn rr = IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, 0, reply, &len);

    if (verbose) {
        printf("  %-14s ->", label);
        for (int i = 0; i < 8; i++) printf(" %02x", buf[i]);
        printf("   reply");
        for (int i = 0; i < 6; i++) printf(" %02x", reply[i]);
        printf("  %s\n", (rr == kIOReturnSuccess && reply[3] == 1) ? "ACK" : "");
    }
    if (rr != kIOReturnSuccess || len < 4) {
        fprintf(stderr, "error: GetReport(%s) failed: 0x%08x (%ld bytes)\n",
                label, rr, (long)len);
        return -1;
    }
    if (want_ack && reply[3] != 1) {
        fprintf(stderr, "error: %s not acknowledged by keyboard\n", label);
        return -1;
    }
    usleep(DELAY);
    return 0;
}

/* Bulk per-key payloads are the documented exception to mandatory read-back. */
static int send_bulk(IOHIDDeviceRef dev, const uint8_t *buf, const char *label) {
    IOReturn result = IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, 0, buf, PKT);
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "error: SetReport(%s) failed: 0x%08x\n", label, result);
        return -1;
    }
    usleep(10000);
    return 0;
}

static void mkcmd(uint8_t *b, uint8_t op) { memset(b, 0, PKT); b[0] = 0x04; b[1] = op; }

/* BEGIN -> SELECT(light) -> payload -> END -> SAVE : the driver's exact sequence */
static int set_light(IOHIDDeviceRef dev, int mode, int r, int g, int bl,
                     int rainbow, int brightness, int speed, int dir) {
    uint8_t b[PKT];
    mkcmd(b, 0x18);                       if (send_pkt(dev, b, "BEGIN", 1)) return -1;
    mkcmd(b, 0x13); b[8] = 1;             if (send_pkt(dev, b, "SELECT", 1)) return -1;

    memset(b, 0, PKT);
    b[0] = (uint8_t)mode;
    b[1] = (uint8_t)r; b[2] = (uint8_t)g; b[3] = (uint8_t)bl;
    b[8] = (uint8_t)rainbow;              /* 0 = use the RGB above, 1 = cycle colors  */
    b[9] = (uint8_t)brightness;           /* 0..5 */
    b[10] = (uint8_t)speed;               /* 0..5 */
    b[11] = (uint8_t)dir;                 /* 0/1  */
    b[14] = 0xAA; b[15] = 0x55;           /* record terminator */
    if (send_pkt(dev, b, "PAYLOAD", 0)) return -1;

    mkcmd(b, 0x02);                       if (send_pkt(dev, b, "END", 1)) return -1;
    mkcmd(b, 0xF0);                       if (send_pkt(dev, b, "SAVE", 1)) return -1;
    return 0;
}

/* ---- per-key lighting (opcode 0x23) --------------------------------------
   Payload is 9 chunks x 64 = 576 bytes. Each LED gets a 4-byte record at
   ledIndex*4: [ledIndex][R][G][B]. Slot 0 stays zero (index 0 = unused),
   and the last two bytes are the AA 55 terminator.
   The keyboard only displays this once light mode 0x80 (user lighting)
   is selected, which is why we send that first.                             */
#define PK_CHUNKS 9
#define PK_LEN   (PK_CHUNKS * PKT)   /* 576 */
#define PK_MAXLED 123

static int set_perkey(IOHIDDeviceRef dev, const uint8_t rgb[][3], int brightness) {
    uint8_t b[PKT];

    /* 1. switch the keyboard into user-lighting mode (0x80) */
    if (set_light(dev, 0x80, 0, 0, 0, 0, brightness, 3, 0)) return -1;

    /* 2. upload the frame */
    mkcmd(b, 0x18);            if (send_pkt(dev, b, "BEGIN", 1)) return -1;
    mkcmd(b, 0x23); b[8] = PK_CHUNKS;
                               if (send_pkt(dev, b, "SELECT pk", 1)) return -1;

    static uint8_t frame[PK_LEN];
    memset(frame, 0, PK_LEN);
    for (int i = 1; i <= PK_MAXLED; i++) {
        frame[i * 4 + 0] = (uint8_t)i;
        frame[i * 4 + 1] = rgb[i][0];
        frame[i * 4 + 2] = rgb[i][1];
        frame[i * 4 + 3] = rgb[i][2];
    }
    frame[PK_LEN - 2] = 0xAA;
    frame[PK_LEN - 1] = 0x55;

    for (int c = 0; c < PK_CHUNKS; c++) {
        char lbl[24]; snprintf(lbl, sizeof lbl, "DATA %d/%d", c + 1, PK_CHUNKS);
        if (send_bulk(dev, frame + c * PKT, lbl)) return -1;
    }

    mkcmd(b, 0x02);            if (send_pkt(dev, b, "END", 1)) return -1;
    mkcmd(b, 0xF0);            if (send_pkt(dev, b, "SAVE", 1)) return -1;
    return 0;
}

/* HSV->RGB for the built-in test patterns */
static void hsv(double h, uint8_t *r, uint8_t *g, uint8_t *b) {
    double s = 1, v = 1, c = v * s, x = c * (1 - fabs(fmod(h / 60.0, 2) - 1));
    double rr = 0, gg = 0, bb = 0;
    if (h < 60)       { rr = c; gg = x; }
    else if (h < 120) { rr = x; gg = c; }
    else if (h < 180) { gg = c; bb = x; }
    else if (h < 240) { gg = x; bb = c; }
    else if (h < 300) { rr = x; bb = c; }
    else              { rr = c; bb = x; }
    *r = (uint8_t)(rr * 255); *g = (uint8_t)(gg * 255); *b = (uint8_t)(bb * 255);
}

static void usage(void) {
    puts(
"aula-s98 \u2014 control AULA S98 Pro lighting natively on macOS\n"
"\n"
"USAGE\n"
"  aula-s98 set <mode> [options]     apply a lighting mode (number or name)\n"
"  aula-s98 off                      turn lighting off\n"
"  aula-s98 perkey [pattern]         solid, rainbow, or alternating\n"
"  aula-s98 list                     list the lighting effects\n"
"  aula-s98 scan [lo] [hi] [secs]    step through modes\n"
"  aula-s98 info                     show the detected device\n"
"\n"
"OPTIONS\n"
"  -c, --color RRGGBB   colour in hex (default ff0000)\n"
"  -b, --brightness N   0-5   (default 5)\n"
"  -s, --speed N        0-5   (default 3)\n"
"  -d, --direction N    0|1   (default 0)\n"
"      --colorful       set the mode-dependent \"colourful\" flag\n"
"  -v, --verbose        print each HID packet and the keyboard\u2019s reply\n"
"\n"
"EXAMPLES\n"
"  aula-s98 set 1 -c 00ff00           solid green\n"
"  aula-s98 set breathing -c ff00ff   breathing magenta\n"
"  aula-s98 set \"rainbow wave\" -s 5  fast rainbow wave\n"
"  aula-s98 perkey rainbow            per-key horizontal rainbow\n"
"  aula-s98 off\n"
"\n"
"There is also a GUI with a colour wheel: ~/Applications/Aula S98 Pro Companion.app");
}

static int parse_number(const char *text, int minimum, int maximum, int *out) {
    char *end = NULL;
    errno = 0;
    long value = strtol(text, &end, 10);
    if (errno || !end || *end || value < minimum || value > maximum) return -1;
    *out = (int)value;
    return 0;
}

static int parse_color(const char *text, int *r, int *g, int *b) {
    const char *raw = text[0] == '#' ? text + 1 : text;
    if (strlen(raw) != 6) return -1;
    /* strtoul skips whitespace and accepts a sign, so the length check alone lets
       " 12345" and "+12345" through and yields a colour the user never typed. */
    for (int i = 0; i < 6; i++)
        if (!isxdigit((unsigned char)raw[i])) return -1;
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(raw, &end, 16);
    if (errno || !end || *end || value > 0xFFFFFFUL) return -1;
    *r = (int)((value >> 16) & 0xFFUL);
    *g = (int)((value >> 8) & 0xFFUL);
    *b = (int)(value & 0xFFUL);
    return 0;
}

static int parse_pattern(const char *text) {
    if (!strcasecmp(text, "solid") || !strcmp(text, "1")) return 1;
    if (!strcasecmp(text, "rainbow") || !strcmp(text, "2")) return 2;
    if (!strcasecmp(text, "alternating") || !strcmp(text, "3")) return 3;
    return -1;
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }

    const char *cmd = argv[1];
    if (!strcmp(cmd, "help") || !strcmp(cmd, "--help") || !strcmp(cmd, "-h")) {
        usage(); return 0;
    }
    if (!strcmp(cmd, "list")) {
        printf("%-4s %-30s %-9s %s\n", "id", "effect", "animated", "uses colour");
        for (int i = 0; i < kNumModes; i++)
            printf("%-4d %-30s %-9s %s\n", kModes[i].id, kModes[i].name,
                   kModes[i].animated ? "yes" : "no", kModes[i].uses_color ? "yes" : "no");
        return 0;
    }
    if (strcmp(cmd, "set") && strcmp(cmd, "off") && strcmp(cmd, "perkey") &&
        strcmp(cmd, "scan") && strcmp(cmd, "info")) {
        fprintf(stderr, "error: unknown command %s\n", cmd);
        usage();
        return 1;
    }

    int mode = 1, r = 0xFF, g = 0, bl = 0;
    int rainbow = 0, brightness = 5, speed = 3, dir = 0;
    int lo = 0, hi = 19, secs = 2, pos = 0;

    for (int i = 2; i < argc; i++) {
        const char *a = argv[i];
        int last = (i + 1 >= argc);
        if (!strcmp(a, "-c") || !strcmp(a, "--color")) {
            if (last) { fprintf(stderr, "error: %s needs RRGGBB\n", a); return 1; }
            if (parse_color(argv[++i], &r, &g, &bl)) {
                fprintf(stderr, "error: colour must be exactly RRGGBB\n"); return 1;
            }
        } else if (!strcmp(a, "-b") || !strcmp(a, "--brightness")) {
            if (last) { fprintf(stderr, "error: %s needs 0-5\n", a); return 1; }
            if (parse_number(argv[++i], 0, 5, &brightness)) {
                fprintf(stderr, "error: brightness must be 0-5\n"); return 1;
            }
        } else if (!strcmp(a, "-s") || !strcmp(a, "--speed")) {
            if (last) { fprintf(stderr, "error: %s needs 0-5\n", a); return 1; }
            if (parse_number(argv[++i], 0, 5, &speed)) {
                fprintf(stderr, "error: speed must be 0-5\n"); return 1;
            }
        } else if (!strcmp(a, "-d") || !strcmp(a, "--direction")) {
            if (last) { fprintf(stderr, "error: %s needs 0|1\n", a); return 1; }
            if (parse_number(argv[++i], 0, 1, &dir)) {
                fprintf(stderr, "error: direction must be 0 or 1\n"); return 1;
            }
        } else if (!strcmp(a, "--colorful") || !strcmp(a, "-r")) {
            rainbow = 1;
        } else if (!strcmp(a, "-v") || !strcmp(a, "--verbose")) {
            verbose = 1;
        } else if (a[0] != '-') {
            if (!strcmp(cmd, "scan")) {
                int value = 0;
                int max = pos < 2 ? 19 : 60;
                int min = pos < 2 ? 0 : 1;
                if (pos > 2 || parse_number(a, min, max, &value)) {
                    fprintf(stderr, "error: scan expects [lo 0-19] [hi 0-19] [seconds 1-60]\n"); return 1;
                }
                if (pos == 0) lo = value; else if (pos == 1) hi = value; else secs = value;
            } else if (!strcmp(cmd, "perkey")) {
                mode = parse_pattern(a);
                if (pos > 0 || mode < 0) {
                    fprintf(stderr, "error: perkey pattern must be solid, rainbow, or alternating\n"); return 1;
                }
            } else if (!strcmp(cmd, "set")) {
                mode = parse_mode(a);
                if (pos > 0 || mode < 0 || mode > 19) {
                    fprintf(stderr, "error: unknown mode \"%s\" (try: aula-s98 list)\n", a); return 1;
                }
            } else {
                fprintf(stderr, "error: %s takes no positional arguments\n", cmd); return 1;
            }
            pos++;
        } else {
            fprintf(stderr, "error: unknown option %s\n", a); return 1;
        }
    }

    if (!strcmp(cmd, "set") && pos == 0) {
        fprintf(stderr, "error: set requires a mode (try: aula-s98 list)\n"); return 1;
    }
    if (!strcmp(cmd, "scan") && lo > hi) {
        fprintf(stderr, "error: scan lower mode must not exceed upper mode\n"); return 1;
    }

    int lock_fd = acquire_process_lock();
    if (lock_fd < 0) return 3;

    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDDeviceRef dev = find_device(mgr);
    if (!dev) {
        fprintf(stderr,
            "error: AULA S98 Pro command interface not found.\n"
            "       Connect the keyboard by USB-C (the wireless dongle uses a different ID).\n");
        CFRelease(mgr);
        flock(lock_fd, LOCK_UN); close(lock_fd);
        return 2;
    }
    if (IOHIDDeviceOpen(dev, kIOHIDOptionsTypeNone) != kIOReturnSuccess) {
        fprintf(stderr, "error: could not open the device.\n");
        CFRelease(dev); CFRelease(mgr);
        flock(lock_fd, LOCK_UN); close(lock_fd);
        return 2;
    }

    int rc = 0;
    if (!strcmp(cmd, "info")) {
        printf("AULA S98 Pro found — VID 0x%04X PID 0x%04X, vendor collection 0x%04X\n", VID, PID, UPAGE);
        printf("64-byte HID Feature channel open and ready.\n");
    } else if (!strcmp(cmd, "perkey")) {
        static uint8_t px[PK_MAXLED + 2][3];
        for (int i = 1; i <= PK_MAXLED; i++) {
            if (mode == 2)        hsv(fmod(i * 360.0 / 40.0, 360), &px[i][0], &px[i][1], &px[i][2]);
            else if (mode == 3) { px[i][0] = (i % 2) ? 255 : 0; px[i][1] = 0; px[i][2] = (i % 2) ? 0 : 255; }
            else                { px[i][0] = (uint8_t)r; px[i][1] = (uint8_t)g; px[i][2] = (uint8_t)bl; }
        }
        rc = set_perkey(dev, (const uint8_t (*)[3])px, brightness);
        if (!rc) printf("per-key frame uploaded (%d LEDs, pattern %d)\n", PK_MAXLED, mode);
    } else if (!strcmp(cmd, "off")) {
        rc = set_light(dev, 0, 0, 0, 0, 0, 0, 0, 0);
        if (!rc) puts("lighting off");
    } else if (!strcmp(cmd, "set")) {
        rc = set_light(dev, mode, r, g, bl, rainbow, brightness, speed, dir);
        if (!rc) printf("%s (mode %d) applied \u2014 colour %02x%02x%02x, brightness %d, speed %d\n",
                        mode_name(mode), mode, r, g, bl, brightness, speed);
    } else if (!strcmp(cmd, "scan")) {
        printf("stepping modes %d..%d, %ds each — note which numbers you like\n", lo, hi, secs);
        for (int m = lo; m <= hi && !rc; m++) {
            printf("  mode %2d  %s\n", m, mode_name(m)); fflush(stdout);
            rc = set_light(dev, m, r, g, bl, rainbow, brightness, speed, dir);
            sleep((unsigned)secs);
        }
    } else {
        usage(); rc = 1;
    }

    IOHIDDeviceClose(dev, kIOHIDOptionsTypeNone);
    CFRelease(dev);
    CFRelease(mgr);
    flock(lock_fd, LOCK_UN);
    close(lock_fd);
    return rc;
}
