//
//  socpwrbud.m
//  socpwrbud
//
//  Copyright (c) 2024 dehydratedpotato
//

#import <Foundation/Foundation.h>
#import <getopt.h>
#import <IOKit/IOKitLib.h>
#import <stdarg.h>
#import <sys/sysctl.h>

#ifdef THEOS
#define kIOMainPortDefault kIOMasterPortDefault
#endif

// External references for IOReport methods

typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;

extern IOReportSubscriptionRef IOReportCreateSubscription(void *, /* NULL */
                                                          CFMutableDictionaryRef desiredChannels,
                                                          CFMutableDictionaryRef *subbedChannels,
                                                          uint64_t               channel_id, /* 0 */
                                                          CFTypeRef /* nil */);

extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef subscription,
                                             CFMutableDictionaryRef  subbedChannels,
                                             CFTypeRef /* nil */);

extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef previousSample,
                                                  CFDictionaryRef currentSample,
                                                  CFTypeRef /* nil */);

extern CFMutableDictionaryRef IOReportCopyChannelsInGroup(NSString *channel,
                                                          NSString * /* nil */,
                                                          uint64_t /* 0 */,
                                                          uint64_t /* 0 */,
                                                          uint64_t /* 0 */);

extern void IOReportMergeChannels(CFMutableDictionaryRef firstChannel,
                                  CFMutableDictionaryRef secondChannel,
                                  CFTypeRef /* nil */);

extern void IOReportIterate(CFDictionaryRef samples, int (^)(CFDictionaryRef channel));

extern NSString * IOReportChannelGetChannelName(CFDictionaryRef);
extern NSString * IOReportChannelGetGroup(CFDictionaryRef);
extern NSString * IOReportChannelGetSubGroup(CFDictionaryRef);

extern int IOReportStateGetCount(CFDictionaryRef);
extern uint64_t IOReportStateGetResidency(CFDictionaryRef, int);
extern NSString * IOReportStateGetNameForIndex(CFDictionaryRef, int);
extern uint64_t IOReportArrayGetValueAtIndex(CFDictionaryRef, int);
extern long IOReportSimpleGetIntegerValue(CFDictionaryRef, int);

// Macros and constants

#define TOOL_VERSION        "v1"

#define METRIC_ACTIVE       "%active"
#define METRIC_IDLE         "%idle"
#define METRIC_FREQ         "freq"
#define METRIC_DVFS         "dvfs"
#define METRIC_DVFSVOLTS    "dvfs_volts"
#define METRIC_VOLTS        "volts"
#define METRIC_CORES        "cores"

#define UNIT_ECPU           "ecpu"
#define UNIT_PCPU           "pcpu"
#define UNIT_GPU            "gpu"

#define METRIC_COUNT        7
#define UNITS_COUNT         3
#define OPT_COUNT           7

#define VOLTAGE_STATES_ECPU CFSTR("voltage-states1-sram")
#define VOLTAGE_STATES_PCPU CFSTR("voltage-states5-sram")
#define VOLTAGE_STATES_GPU  CFSTR("voltage-states9")

typedef struct param_set {
    const char *name;
    const char *description;
} param_set;

static const struct param_set metrics_set[METRIC_COUNT] = {
    {
        METRIC_ACTIVE,   "active residencies"
    },
    {
        METRIC_IDLE,     "idle residencies"
    },
    {
        METRIC_FREQ,     "active frequencies"
    },
    {
        METRIC_DVFS,     "dvfs (or pstate) distributions, unoccupied states hidden"
    },
    {
        METRIC_DVFSVOLTS, "(milli)volts label on dvfs"
    },
    {
        METRIC_VOLTS,    "display (m)voltages"
    },
    {
        METRIC_CORES,    "per-core stats on supported units"
    }
};

static const struct param_set units_set[UNITS_COUNT] = {
    {
        UNIT_ECPU, "efficiency cluster(s) stats"
    },
    {
        UNIT_PCPU, "performance cluster(s) stats"
    },
    {
        UNIT_GPU,  "integrated graphics stats"
    },
};

static const struct option long_opts[OPT_COUNT] = {
    {
        "help", no_argument, 0, 'h'
    },
    {
        "version", no_argument, 0, 'v'
    },
    {
        "interval", required_argument, 0, 'i'
    },
    {
        "samples", required_argument, 0, 's'
    },
    {
        "hide-unit", required_argument, 0, 'H'
    },
    {
        "metrics", required_argument, 0, 'm'
    },
    {
        "all-metrics", no_argument, 0, 'a'
    },
};

static const char *long_opts_description[OPT_COUNT] = {
    "               print this message and exit\n",
    "            print tool version number and exit\n\n",
    " <N>       perform samples between N ms [default: 175ms]\n",
    " <N>        collect and display N samples (0=inf) [default: 1]\n",
    " <unit>   comma separated list of unit statistics to hide\n",
    " <metrics>  comma separated list of metrics to report\n",
    "        report all available metrics for the visible units\n\n",
};

static NSString *const CPU_COMPLEX_PERF_STATES_SUBGROUP = @"CPU Complex Performance States";
static NSString *const CPU_CORE_PERF_STATES_SUBGROUP = @"CPU Core Performance States";
static NSString *const GPU_PERF_STATES_SUBGROUP = @"GPU Performance States";

static NSArray<NSString *> *const performanceCounterKeys = @[
    @"ECPU", @"PCPU",                         /* pleb chips (M1, M2, M3, M3 Pro) */
    @"ECPU0", @"PCPU0", @"PCPU1",             /* Max Chips */
    @"EACC_CPU", @"PACC0_CPU", @"PACC1_CPU",  /* Ultra Chips */
];

static NSString *const P_STATE = @"P";
static NSString *const V_STATE = @"V";
static NSString *const IDLE_STATE = @"IDLE";
static NSString *const OFF_STATE = @"OFF";

typedef struct cmd_data {
    int interval; /* sleep time between samples */
    int samples;  /* target samples to make */

    struct {
        bool hide_ecpu;
        bool hide_pcpu;
        bool hide_gpu;
        bool show_active;
        bool show_idle;
        bool show_freq;
        bool show_volts;
        bool show_percore;
        bool show_dvfs;
        bool show_dvfs_volts;
    } flags;
} cmd_data;

__attribute__((visibility("hidden")))
@interface TRSocStat : NSObject {
@public
    NSString *_name;

    NSMutableArray *_children;
    NSMutableDictionary *_childrenMapping;

    NSArray<NSArray<NSNumber *> *> *_dvfs;
    NSMutableArray<NSNumber *> *_pstate_distribution;

    uint32_t _is_in_use;
    uint32_t _state_count;

    float _freq;
    float _mvolts;
    float _active;
    float _idle;
}

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, assign, readonly) BOOL isInUse;

@property (nonatomic, assign, readonly) float frequencyMHz;
@property (nonatomic, assign, readonly) float millivolts;

@property (nonatomic, assign, readonly) float activeResidency; // in percent
@property (nonatomic, assign, readonly) float idleResidency;   // in percent

- (NSArray<TRSocStat *> *)children;

@end

@implementation TRSocStat

- (NSString *)name {
    return _name;
}

- (BOOL)isInUse {
    return _is_in_use;
}

- (float)frequencyMHz {
    return _freq;
}

- (float)millivolts {
    return _mvolts;
}

- (float)activeResidency {
    return _active;
}

- (float)idleResidency {
    return _idle;
}

- (NSArray<TRSocStat *> *)children {
    return [_children copy];
}

@end

static NSString * getPlatformName(void) {
    io_registry_entry_t entry;
    io_iterator_t iter;

    CFMutableDictionaryRef servicedict;
    CFMutableDictionaryRef service;

    if (!(service = IOServiceMatching("IOPlatformExpertDevice"))) {
        return nil;
    }

    if (!(IOServiceGetMatchingServices(kIOMainPortDefault, service, &iter) == kIOReturnSuccess)) {
        return nil;
    }

    NSString *platfromName = nil;

    while ((entry = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        if ((IORegistryEntryCreateCFProperties(entry, &servicedict, kCFAllocatorDefault, 0) != kIOReturnSuccess)) {
            return nil;
        }

        const void *data = CFDictionaryGetValue(servicedict, @"platform-name");

        if (data != nil) {
            NSData *formattedData = (NSData *)CFBridgingRelease(data);
            const unsigned char *dataBytes = [formattedData bytes];

            platfromName = [[NSString stringWithFormat:@"%s", dataBytes] capitalizedString];

            formattedData = nil;
        }
    }

    IOObjectRelease(entry);
    IOObjectRelease(iter);

    return platfromName;
}

static void getDfvs(io_registry_entry_t entry, CFStringRef string, NSMutableArray *dvfs) {
    const void *data = IORegistryEntryCreateCFProperty(entry, string, kCFAllocatorDefault, 0);

    [dvfs addObject:@[@0, @0]];

    if (data != nil) {
        NSData *formattedData = (NSData *)CFBridgingRelease(data);
        const unsigned char *databytes = [formattedData bytes];

        for (int ii = 0; ii < [formattedData length] - 4; ii += 8) {
            uint32_t freqDword = *(uint32_t *)(databytes + ii) * 1e-6;
            uint32_t voltDword = *(uint32_t *)(databytes + ii + 4);

            if (freqDword != 0) {
                NSNumber *freq = [NSNumber numberWithUnsignedInt:freqDword];
                NSNumber *mvolt = [NSNumber numberWithUnsignedInt:voltDword];

                [dvfs addObject:@[freq, mvolt]];
            }
        }

        formattedData = nil;
    }
}

static void makeDvfsTables(NSMutableArray *ecpu_table, NSMutableArray *pcpu_table, NSMutableArray *gpu_table) {
    io_registry_entry_t entry;
    io_iterator_t iter;
    CFMutableDictionaryRef service;

    if (!(service = IOServiceMatching("AppleARMIODevice"))) {
        return;
    }

    if (!(IOServiceGetMatchingServices(kIOMainPortDefault, service, &iter) == kIOReturnSuccess)) {
        return;
    }

    while ((entry = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        if (IORegistryEntryCreateCFProperty(entry, VOLTAGE_STATES_ECPU, kCFAllocatorDefault, 0) != nil) {
            getDfvs(entry, VOLTAGE_STATES_ECPU, ecpu_table);
            getDfvs(entry, VOLTAGE_STATES_PCPU, pcpu_table);
            getDfvs(entry, VOLTAGE_STATES_GPU, gpu_table);
            break;
        }
    }

    IOObjectRelease(entry);
    IOObjectRelease(iter);
}

static TRSocStat * makeStats(NSString *name, NSArray *dvfs) {
    TRSocStat *stat = [[TRSocStat alloc] init];

    stat->_name = name;
    stat->_dvfs = dvfs;
    stat->_state_count = (uint32_t)[stat->_dvfs count];

    int pstate_distribution_size = stat->_state_count * sizeof(float);
    stat->_pstate_distribution = [[NSMutableArray alloc] initWithCapacity:pstate_distribution_size];

    while (pstate_distribution_size--)
        [stat->_pstate_distribution addObject:@0];

    return stat;
}

static NSMutableDictionary * filterChannelAndConstructCollection(CFMutableDictionaryRef channel) {
    NSMutableArray *ecpuDvfs = [[NSMutableArray alloc] init];
    NSMutableArray *pcpuDvfs = [[NSMutableArray alloc] init];
    NSMutableArray *gpuDvfs = [[NSMutableArray alloc] init];

    makeDvfsTables(ecpuDvfs, pcpuDvfs, gpuDvfs);

    NSMutableDictionary *collection = [[NSMutableDictionary alloc] init];
    CFMutableArrayRef array = (CFMutableArrayRef)CFDictionaryGetValue(channel, CFSTR("IOReportChannels"));

    for (int i = (int)CFArrayGetCount(array); i--;) {
        CFDictionaryRef dict = CFArrayGetValueAtIndex(array, i);
        NSString *subgroup = CFDictionaryGetValue(dict, CFSTR("IOReportSubGroupName"));

        if (![subgroup isEqualToString:CPU_CORE_PERF_STATES_SUBGROUP]) {
            if ([subgroup isEqualToString:CPU_COMPLEX_PERF_STATES_SUBGROUP]) {
                CFArrayRef legendChannel = (CFArrayRef)CFDictionaryGetValue(dict, CFSTR("LegendChannel"));
                NSString *channelName = CFArrayGetValueAtIndex(legendChannel, 2);

                if (![channelName containsString:@"CPM"]) {
                    TRSocStat *stat;

                    if ([channelName containsString:@"E"]) {
                        stat = makeStats(channelName, ecpuDvfs);
                    } else {
                        stat = makeStats(channelName, pcpuDvfs);
                    }

                    stat->_children = [[NSMutableArray alloc] init];
                    stat->_childrenMapping = [[NSMutableDictionary alloc] init];

                    [collection setObject:stat forKey:channelName];
                }

                channelName = nil;
            } else if ([subgroup isEqualToString:GPU_PERF_STATES_SUBGROUP]) {
                NSString *channelName = @"GPUPH";

                TRSocStat *stat = makeStats(channelName, gpuDvfs);
                [collection setObject:stat forKey:channelName];

                channelName = nil;
            } else {
                CFArrayRemoveValueAtIndex(array, i);
            }
        }

        subgroup = nil;
    }

    IOReportIterate(channel, ^int (CFDictionaryRef channel) {
        NSString *subgroup = IOReportChannelGetSubGroup(channel);

        if (![subgroup isEqualToString:CPU_CORE_PERF_STATES_SUBGROUP]) {
            return 0;
        }

        NSString *channelName = IOReportChannelGetChannelName(channel);
        NSString *parentName = [channelName substringToIndex:[channelName length] - 1];
        TRSocStat *parent = [collection objectForKey:parentName];

        if (parent != nil) {
            TRSocStat *core;

            if ([channelName containsString:@"E"]) {
                core = makeStats(channelName, ecpuDvfs);
            } else {
                core = makeStats(channelName, pcpuDvfs);
            }

            [parent->_children addObject:core];
            [parent->_childrenMapping setObject:core forKey:channelName];
        }

        channelName = nil;
        subgroup = nil;

        return 0;
    });

    return collection;
}

static void update(TRSocStat *stat, CFDictionaryRef channel) {
    uint64_t idle_residency = IOReportStateGetResidency(channel, 0);
    uint64_t residencies_sum = 0;

    for (int i = 1; i < stat->_state_count; i++) {
        NSString *indexName = IOReportStateGetNameForIndex(channel, i);
        uint64_t residency = IOReportStateGetResidency(channel, i);

        if ([indexName containsString:P_STATE] || [indexName containsString:V_STATE]) {
            residencies_sum += residency;

            stat->_pstate_distribution[i] = @((float)residency);
        }

        indexName = nil;
    }

    float freq_sum = 0;
    float mvolt_sum = 0;

    float multiplier = 1 / (float)residencies_sum;

    for (int i = 1; i < stat->_state_count; i++) {
        if (residencies_sum == 0) {
            break;
        }

        NSArray<NSNumber *> *state = stat->_dvfs[i];

        float distribtion = [stat->_pstate_distribution[i] floatValue] * multiplier;
        float freq = distribtion * [state[0] floatValue];
        float mvolt = distribtion * [state[1] floatValue];

        freq_sum += freq;
        mvolt_sum += mvolt;

        stat->_pstate_distribution[i] = @(distribtion);
    }

    uint64_t complete_sum = residencies_sum + idle_residency;

    stat->_freq = freq_sum;
    stat->_mvolts = mvolt_sum;

    if (complete_sum != 0) {
        stat->_active = ((float)residencies_sum / complete_sum) * 100;
        stat->_idle = ((float)idle_residency / complete_sum) * 100;
    } else {
        stat->_active = 0;
        stat->_idle = 0;
    }

    stat->_is_in_use = stat->_idle != 0;
}

static void updateLoop(NSDictionary *collection, CFDictionaryRef sample) {
    IOReportIterate(sample, ^int (CFDictionaryRef channel) {
        NSString *subgroup = IOReportChannelGetSubGroup(channel);
        NSString *channelName = IOReportChannelGetChannelName(channel);

        if ([subgroup isEqualToString:CPU_COMPLEX_PERF_STATES_SUBGROUP] || [subgroup isEqualToString:GPU_PERF_STATES_SUBGROUP]) {
            TRSocStat *parent = [collection objectForKey:channelName];

            if (parent != nil) {
                update(parent, channel);
            }
        } else if ([subgroup isEqualToString:CPU_CORE_PERF_STATES_SUBGROUP]) {
            NSString *parentName = [channelName substringToIndex:[channelName length] - 1];
            TRSocStat *parent = [collection objectForKey:parentName];

            if (parent != nil) {
                TRSocStat *core = [parent->_childrenMapping objectForKey:channelName];

                if (core != nil) {
                    update(core, channel);
                }
            }
        }

        channelName = nil;
        subgroup = nil;

        return 0;
    });
}

static void print(NSDictionary *collection, cmd_data *cmd) {
    for (NSString *key in collection) {
        TRSocStat *parent = [collection objectForKey:key];

        if (([parent->_name containsString:@"E"] && cmd->flags.hide_ecpu) ||
            ([parent->_name containsString:@"P"] && cmd->flags.hide_pcpu) ||
            ([parent->_name containsString:@"G"] && cmd->flags.hide_gpu)) {
            continue;
        }

        if ([parent->_name isEqualToString:@"GPUPH"]) {
            fprintf(stdout, "Integrated Graphics \n");
        } else {
            fprintf(stdout, "%ld-Core %s\n", [parent->_children count], parent->_name.UTF8String);
        }

        if (cmd->flags.show_freq) {
            fprintf(stdout, "    Average frequency: %.0f mHz\n", parent->_freq);
        }

        if (cmd->flags.show_volts) {
            fprintf(stdout, "    Average voltage:   %.0f mV\n", parent->_mvolts);
        }

        if (cmd->flags.show_active) {
            fprintf(stdout, "    Active residency:  %.2f %%\n", parent->_active);
        }

        if (cmd->flags.show_idle) {
            fprintf(stdout, "    Idle residency:    %.2f %%\n\n", parent->_idle);
        }

        if (cmd->flags.show_dvfs) {
            fprintf(stdout, "    DVFS distribution:\n");

            int counter = 0;

            for (int i = 0; i < parent->_state_count; i++) {
                float value = [parent->_pstate_distribution[i] floatValue] * 100;

                if (value > 0.009) {
                    fprintf(stdout, "        %.f mHz", [parent->_dvfs[i][0] floatValue]);

                    if (cmd->flags.show_dvfs_volts) {
                        fprintf(stdout, " (%.f mV)", [parent->_dvfs[i][1] floatValue]);
                    }

                    fprintf(stdout, ": %.2f %%\n", value);

                    counter++;
                }
            }

            if (counter == 0) {
                fprintf(stdout, "        none\n");
            }

            printf("\n");
        }

        if (parent->_children != nil && parent->_childrenMapping != nil && cmd->flags.show_percore) {
            for (int i = 0; i < [parent->_children count]; i++) {
                TRSocStat *core = parent->_children[i];

                fprintf(stdout, "    Core #%d\n", i);

                if (cmd->flags.show_freq) {
                    fprintf(stdout, "        Average frequency: %.0f mHz\n", core->_freq);
                }

                if (cmd->flags.show_volts) {
                    fprintf(stdout, "        Average voltage:   %.0f mV\n", core->_mvolts);
                }

                if (cmd->flags.show_active) {
                    fprintf(stdout, "        Active residency:  %.2f %%\n", core->_active);
                }

                if (cmd->flags.show_idle) {
                    fprintf(stdout, "        Idle residency:    %.2f %%\n", core->_idle);
                }

                if (cmd->flags.show_dvfs) {
                    fprintf(stdout, "\n        DVFS distribution:\n");

                    int counter = 0;

                    for (int i = 0; i < core->_state_count; i++) {
                        float value = [core->_pstate_distribution[i] floatValue] * 100;

                        if (value > 0.009) {
                            fprintf(stdout, "            %.f mHz", [parent->_dvfs[i][0] floatValue]);

                            if (cmd->flags.show_dvfs_volts) {
                                fprintf(stdout, " (%.f mv)", [parent->_dvfs[i][1] floatValue]);
                            }

                            fprintf(stdout, ": %.2f %%\n", value);

                            counter++;
                        }
                    }

                    if (counter == 0) {
                        fprintf(stdout, "            none\n");
                    }
                }

                fprintf(stdout, "\n");
            }
        }
    }
}

static NSString * getSocName(void) {
    size_t len;

    sysctlbyname("machdep.cpu.brand_string", NULL, &len, NULL, 0);

    char *cpuBrand = malloc(len);
    sysctlbyname("machdep.cpu.brand_string", cpuBrand, &len, NULL, 0);

    NSString *brand = [NSString stringWithUTF8String:cpuBrand];
    free(cpuBrand);

    return brand;
}

static void help(void) {
    fprintf(stdout, "\nUsage: %s [-a] [-i interval] [-s samples]\n\n\e[0m", getprogname());
    fprintf(stdout, "  A sudoless tool to profile your Apple M-Series CPU+GPU active core\n  and cluster frequencies, residencies, and performance states.\n  Inspired by Powermetrics. Thrown together by dehydratedpotato.\n\nThe following command-line options are supported:\e[0m\n\n");

    for (int i = 0; i < OPT_COUNT; i++) {
        fprintf(stdout, "    -%c, --%s%s", long_opts[i].val, long_opts[i].name, long_opts_description[i]);
    }

    fprintf(stdout, "The following are metrics supported by --metrics:\e[0m\n\n");

    for (int i = 0; i < METRIC_COUNT; i++) {
        fprintf(stdout, "    %-15s%s\n", metrics_set[i].name, metrics_set[i].description);
    }

    fprintf(stdout, "\n    default: %s,%s,%s,%s\n\nThe following are units supported by --hide-units:\e[0m\n\n", METRIC_ACTIVE, METRIC_IDLE, METRIC_FREQ, METRIC_CORES);

    for (int i = 0; i < UNITS_COUNT; i++) {
        fprintf(stdout, "    %-15s%s\n", units_set[i].name, units_set[i].description);
    }

    exit(0);
}

static inline void init_cmd_data(cmd_data *data) {
    memset((void *)data, 0, sizeof(cmd_data));

    data->interval = 275;
    data->samples = 1;

    data->flags.show_active = true;
    data->flags.show_idle = true;
    data->flags.show_freq = true;
    data->flags.show_percore = true;
}

static void error(int exitcode, const char *format, ...) {
    va_list args;

    fprintf(stderr, "%s:\033[0;31m error:\033[0m\e[0m ", getprogname());

    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fprintf(stderr, "\n");

    exit(exitcode);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *socName = getSocName();
        NSString *platformName = getPlatformName();

        CFMutableDictionaryRef subscriptionChannel = nil;
        CFMutableDictionaryRef cpuChannel = IOReportCopyChannelsInGroup(@"CPU Stats", nil, 0, 0, 0);
        CFMutableDictionaryRef gpuChannel = IOReportCopyChannelsInGroup(@"GPU Stats", nil, 0, 0, 0);

        IOReportMergeChannels(cpuChannel, gpuChannel, nil);

        CFMutableDictionaryRef channel = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(cpuChannel), cpuChannel);
        NSMutableDictionary *collection = filterChannelAndConstructCollection(channel);

        IOReportSubscriptionRef subscription = IOReportCreateSubscription(NULL, channel, &subscriptionChannel, 0, nil);

        if (!subscription) {
            error(EXIT_FAILURE, "Failed to create IOReport subscription");
        }

        static cmd_data globalCmd;
        cmd_data *cmd = &globalCmd;
        init_cmd_data(cmd);

        NSString *active_metrics_str = nil;
        NSArray *active_metrics_list = nil;
        NSString *hide_units_str = nil;
        NSArray *hide_units_list = nil;

        int opt = 0;
        int optindex = 0;

        while ((opt = getopt_long(argc, argv, "hvi:s:po:m:H:wga", long_opts, &optindex)) != -1) {
            switch (opt) {
                case '?':
                case 'h':
                    help();

                case 'v':
                    printf("%s %s (build %s %s)\n", getprogname(), TOOL_VERSION, __DATE__, __TIME__);
                    return EXIT_SUCCESS;

                case 'i':
                    cmd->interval = atoi(optarg);

                    if (cmd->interval < 1) {
                        cmd->interval = 1;
                    }

                    break;

                case 's':
                    cmd->samples = atoi(optarg);

                    if (cmd->samples <= 0) {
                        cmd->samples = -1;
                    }

                    break;

                case 'm':
                    active_metrics_str = [NSString stringWithFormat:@"%s", strdup(optarg)];
                    active_metrics_list = [active_metrics_str componentsSeparatedByString:@","];
                    active_metrics_str = nil;

                    memset(&cmd->flags, 0, sizeof(cmd->flags));

                    for (int i = 0; i < [active_metrics_list count]; i++) {
                        NSString *string = [active_metrics_list[i] lowercaseString];

                        if ([string isEqualToString:[NSString stringWithUTF8String:METRIC_ACTIVE]]) {
                            cmd->flags.show_active = true;
                        } else if ([string isEqualToString:[NSString stringWithUTF8String:METRIC_IDLE]]) {
                            cmd->flags.show_idle = true;
                        } else if ([string isEqualToString:[NSString stringWithUTF8String:METRIC_FREQ]]) {
                            cmd->flags.show_freq = true;
                        } else if ([string isEqualToString:[NSString stringWithUTF8String:METRIC_VOLTS]]) {
                            cmd->flags.show_volts = true;
                        } else if ([string isEqualToString:[NSString stringWithUTF8String:METRIC_CORES]]) {
                            cmd->flags.show_percore = true;
                        } else if ([string isEqualToString:[NSString stringWithUTF8String:METRIC_DVFS]]) {
                            cmd->flags.show_dvfs = true;
                        } else if ([string isEqualToString:[NSString stringWithUTF8String:METRIC_DVFSVOLTS]]) {
                            cmd->flags.show_dvfs_volts = true;
                        } else {
                            error(EXIT_FAILURE, "Incorrect metric option \"%s\" in list", [string UTF8String]);
                        }
                    }

                    active_metrics_list = nil;
                    break;

                case 'H':
                    hide_units_str = [NSString stringWithFormat:@"%s", strdup(optarg)];
                    hide_units_list = [hide_units_str componentsSeparatedByString:@","];
                    hide_units_str = nil;

                    for (int i = 0; i < [hide_units_list count]; i++) {
                        NSString *string = [hide_units_list[i] lowercaseString];

                        if ([string isEqualToString:@"ecpu"]) {
                            cmd->flags.hide_ecpu = true;
                        } else if ([string isEqualToString:@"pcpu"]) {
                            cmd->flags.hide_pcpu = true;
                        } else if ([string isEqualToString:@"gpu"]) {
                            cmd->flags.hide_gpu = true;
                        } else {
                            error(EXIT_FAILURE, "Incorrect unit option \"%s\" in list", [string UTF8String]);
                        }
                    }

                    hide_units_list = nil;
                    break;

                case 'a':
                    cmd->flags.show_active = true;
                    cmd->flags.show_idle = true;
                    cmd->flags.show_freq = true;
                    cmd->flags.show_volts = true;
                    cmd->flags.show_dvfs = true;
                    cmd->flags.show_dvfs_volts = true;
                    cmd->flags.show_percore = true;
                    break;
            }
        }

        fprintf(stdout, "Profiling %s (%s)...\n\n", socName.UTF8String, platformName.UTF8String);

        for (; cmd->samples--;) {
            @autoreleasepool {
                CFDictionaryRef firstSample = IOReportCreateSamples(subscription, subscriptionChannel, NULL);
                [NSThread sleepForTimeInterval:(float)cmd->interval * 1e-3];

                CFDictionaryRef lastSample = IOReportCreateSamples(subscription, subscriptionChannel, NULL);
                CFDictionaryRef sampleDelta = IOReportCreateSamplesDelta(firstSample, lastSample, NULL);

                updateLoop(collection, sampleDelta);
                print(collection, cmd);

                if (firstSample) {
                    CFRelease(firstSample);
                }

                if (lastSample) {
                    CFRelease(lastSample);
                }

                if (sampleDelta) {
                    CFRelease(sampleDelta);
                }
            }
        }

        return EXIT_SUCCESS;
    }
}
