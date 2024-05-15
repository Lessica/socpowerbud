//
//  main.m - socpwrbud
//
//  Copyright (c) 2024 dehydratedpotato
//

#import <Foundation/Foundation.h>
#import <sys/sysctl.h>
#import <getopt.h>
#import <stdarg.h>

// External references for IOReport methods

typedef struct IOReportSubscriptionRef* IOReportSubscriptionRef;

extern IOReportSubscriptionRef IOReportCreateSubscription(void*, /* NULL */
                                                          CFMutableDictionaryRef desiredChannels,
                                                          CFMutableDictionaryRef* subbedChannels,
                                                          uint64_t channel_id,/* 0 */
                                                          CFTypeRef /* nil */ );

extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef subscription,
                                             CFMutableDictionaryRef subbedChannels,
                                             CFTypeRef /* nil */);

extern CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef previousSample,
                                                  CFDictionaryRef currentSample,
                                                  CFTypeRef /* nil */ );

extern CFMutableDictionaryRef IOReportCopyChannelsInGroup(NSString* channel,
                                                          NSString* /* nil */,
                                                          uint64_t /* 0 */,
                                                          uint64_t /* 0 */,
                                                          uint64_t /* 0 */);

extern void IOReportMergeChannels(CFMutableDictionaryRef firstChannel,
                                  CFMutableDictionaryRef secondChannel,
                                  CFTypeRef /* nil */);

extern void IOReportIterate(CFDictionaryRef samples, int(^)(CFDictionaryRef channel));

extern NSString* IOReportChannelGetChannelName(CFDictionaryRef);
extern NSString* IOReportChannelGetGroup(CFDictionaryRef);
extern NSString* IOReportChannelGetSubGroup(CFDictionaryRef);

extern int IOReportStateGetCount(CFDictionaryRef);
extern uint64_t IOReportStateGetResidency(CFDictionaryRef, int);
extern NSString* IOReportStateGetNameForIndex(CFDictionaryRef, int);
extern uint64_t IOReportArrayGetValueAtIndex(CFDictionaryRef, int);
extern long IOReportSimpleGetIntegerValue(CFDictionaryRef, int);

// Macros and constants

#define TOOL_VERSION "v1"

#define METRIC_ACTIVE     "%active"
#define METRIC_IDLE       "%idle"
#define METRIC_FREQ       "freq"
#define METRIC_DVFS       "dvfs"
#define METRIC_DVFSVOLTS  "dvfs_volts"
//#define METRIC_POWER      "power"
#define METRIC_VOLTS      "volts"
#define METRIC_CORES      "cores"

#define UNIT_ECPU         "ecpu"
#define UNIT_PCPU         "pcpu"
#define UNIT_GPU          "gpu"

#define METRIC_COUNT 7
#define UNITS_COUNT 3
#define OPT_COUNT 7

#define VOLTAGE_STATES_ECPU CFSTR("voltage-states1-sram")
#define VOLTAGE_STATES_PCPU CFSTR("voltage-states5-sram")
#define VOLTAGE_STATES_GPU CFSTR("voltage-states9")

typedef struct param_set {
    const char* name;
    const char* description;
} param_set;

static const struct param_set metrics_set[METRIC_COUNT] = {
    { METRIC_ACTIVE,   "active residencies" },
    { METRIC_IDLE,     "idle residencies" },
    { METRIC_FREQ,     "active frequencies" },
    { METRIC_DVFS,     "dvfs (or pstate) distributions, unoccupied states hidden" },
    { METRIC_DVFSVOLTS,"(milli)volts label on dvfs" },
//    { METRIC_POWER,    "unit power consumptions" },
    { METRIC_VOLTS,    "display (m)voltages" },
    { METRIC_CORES,    "per-core stats on supported units" }
};

static const struct param_set units_set[UNITS_COUNT] = {
    { UNIT_ECPU, "efficiency cluster(s) stats" },
    { UNIT_PCPU, "performance cluster(s) stats" },
    { UNIT_GPU,  "integrated graphics stats" },
};

static const struct option long_opts[OPT_COUNT] = {
    { "help", no_argument, 0, 'h' },
    { "version", no_argument, 0, 'v' },
    { "interval", required_argument, 0, 'i' },
    { "samples", required_argument, 0, 's' },
//    { "output", required_argument, 0, 'o' },
    { "hide-unit", required_argument, 0, 'H' },
    { "metrics", required_argument, 0, 'm' },
    { "all-metrics", no_argument, 0, 'a' },
//    { "property-list", no_argument, 0, 'p' },
};

static const char* long_opts_description[OPT_COUNT] = {
    "               print this message and exit\n",
    "            print tool version number and exit\n\n",
    " <N>       perform samples between N ms [default: 175ms]\n",
    " <N>        collect and display N samples (0=inf) [default: 1]\n",
//    " <file>      set a file for metric stdout\n\n",
    " <unit>   comma separated list of unit statistics to hide\n",
    " <metrics>  comma separated list of metrics to report\n",
    "        report all available metrics for the visible units\n\n",
//    "          set power measurement to watts (default is mW)\n",
};

static const NSString* CPU_COMPLEX_PERF_STATES_SUBGROUP = @"CPU Complex Performance States";
static const NSString* CPU_CORE_PERF_STATES_SUBGROUP = @"CPU Core Performance States";
static const NSString* GPU_PERF_STATES_SUBGROUP = @"GPU Performance States";

static const NSArray* performanceCounterKeys = @[ @"ECPU", @"PCPU", /* pleb chips (M1, M2, M3, M3 Pro) */
                                                  @"ECPU0", @"PCPU0", @"PCPU1", /* Max Chips */
                                                  @"EACC_CPU", @"PACC0_CPU", @"PACC1_CPU" /* Ultra Chips */];

static NSString* P_STATE     = @"P";
static NSString* V_STATE     = @"V";
static NSString* IDLE_STATE  = @"IDLE";
//static const NSString* DOWN_STATE  = @"DOWN";
static NSString* OFF_STATE   = @"OFF";

typedef struct cmd_data {
    int interval; /* sleep time between samples */
    int samples; /* target samples to make */
    
//    bool plist;
//    FILE* file_out;
    
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
//        bool show_pwr;
    } flags;
} cmd_data;

typedef struct stats {
    NSString* name;
    
    NSMutableArray* childrenAray;
    NSMutableDictionary* childrenDictionary;
    
    NSArray* dvfs;
    float* pstate_distribution;
    
    uint32_t is_in_use;
    uint32_t state_count;
    
    float freq;
    //        float power;
    float mvolts;
    float active;
    float idle;
} stats;

NSString* getPlatformName(void)  {
    io_registry_entry_t entry;
    io_iterator_t  iter;
    
    CFMutableDictionaryRef servicedict;
    CFMutableDictionaryRef service;
    
    if (!(service = IOServiceMatching("IOPlatformExpertDevice"))) return nil;
    if (!(IOServiceGetMatchingServices(kIOMainPortDefault, service, &iter) == kIOReturnSuccess)) return nil;
    
    NSString* platfromName = nil;
    
    while ((entry = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        if ((IORegistryEntryCreateCFProperties(entry, &servicedict, kCFAllocatorDefault, 0) != kIOReturnSuccess)) return nil;
        
        const void* data = CFDictionaryGetValue(servicedict, @"platform-name");;
        
        if (data != nil) {
            NSData* formattedData = (NSData*)CFBridgingRelease(data);
            const unsigned char* databytes = [formattedData bytes];
            
            platfromName = [[NSString stringWithFormat:@"%s", databytes] capitalizedString];
            
            formattedData = nil;
        }
    }
    
    IOObjectRelease(entry);
    IOObjectRelease(iter);
    
    return platfromName;
}

static void getDfvs(io_registry_entry_t entry, CFStringRef string, NSMutableArray* dvfs) {
    const void* data = IORegistryEntryCreateCFProperty(entry, string, kCFAllocatorDefault, 0);
    
    [dvfs addObject:@[@0, @0]];
    
    if (data != nil) {
        NSData* formattedData = (NSData*)CFBridgingRelease(data);
        const unsigned char* databytes = [(NSData*)CFBridgingRelease(data) bytes];
        
        for (int ii = 0; ii < [formattedData length] - 4; ii += 8) {
            uint32_t freqDword = *(uint32_t*)(databytes + ii) * 1e-6;
            uint32_t voltDword = *(uint32_t*)(databytes + ii + 4);
            
            if (freqDword != 0) {
                NSNumber* freq = [NSNumber numberWithUnsignedInt:freqDword];
                NSNumber* mvolt = [NSNumber numberWithUnsignedInt:voltDword];
                
                [dvfs addObject: @[freq, mvolt]];
            }
        }
        
        formattedData = nil;
    }
}

static void makeDvfsTables(NSMutableArray* ecpu_table, NSMutableArray* pcpu_table, NSMutableArray* gpu_table) {
    io_registry_entry_t entry;
    io_iterator_t iter;
    CFMutableDictionaryRef service;
    
    if (!(service = IOServiceMatching("AppleARMIODevice"))) return;
    if (!(IOServiceGetMatchingServices(kIOMainPortDefault, service, &iter) == kIOReturnSuccess)) return;
    
    while ((entry = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        /* check if the first voltage state is here. if so, the others should be... kinda gross, should probably fix this later
         */
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

stats* makeStats(NSString* name, NSArray* dvfs) {
    stats* stat = malloc(sizeof(stats));
    
    stat->name = name;
    stat->dvfs = dvfs;
    stat->state_count = (uint32_t)[stat->dvfs count];
    
    int pstate_distribution_size = stat->state_count * sizeof(float);
    stat->pstate_distribution = malloc(pstate_distribution_size);
    
    return stat;
}

NSMutableDictionary* filterChannelAndConstructCollection(CFMutableDictionaryRef channel) {
    NSMutableArray* ecpuDvfs = [[NSMutableArray alloc] init];
    NSMutableArray* pcpuDvfs = [[NSMutableArray alloc] init];;
    NSMutableArray* gpuDvfs = [[NSMutableArray alloc] init];;
    
    makeDvfsTables(ecpuDvfs, pcpuDvfs, gpuDvfs);
    
    NSMutableDictionary* collection = [[NSMutableDictionary alloc] init];
    CFMutableArrayRef array = (CFMutableArrayRef)CFDictionaryGetValue(channel, CFSTR("IOReportChannels"));
    
    for (int i = (int)CFArrayGetCount(array); i--;) {
        CFDictionaryRef dict = CFArrayGetValueAtIndex(array, i);
        NSString* subgroup = CFDictionaryGetValue(dict, CFSTR("IOReportSubGroupName"));
        
        if ([subgroup isNotEqualTo: CPU_CORE_PERF_STATES_SUBGROUP]) {
            if ([subgroup isEqual: CPU_COMPLEX_PERF_STATES_SUBGROUP]) {
                
                // The channel name is originally the last (third) item in the legend
                CFArrayRef legendChannel = (CFArrayRef)CFDictionaryGetValue(dict, CFSTR("LegendChannel"));
                NSString* channelName = CFArrayGetValueAtIndex(legendChannel, 2);
                
                if (![channelName containsString:@"CPM"]) { // we want to filter out CPMs
                    stats* stat;
                    
                    if ([channelName containsString:@"E"]) {
                        stat = makeStats(channelName, ecpuDvfs );
                    } else {
                        stat = makeStats(channelName, pcpuDvfs );
                    }
                    
                    stat->childrenAray = [[NSMutableArray alloc] init];
                    stat->childrenDictionary = [[NSMutableDictionary alloc] init];
                    
                    NSValue* pointer = [NSValue valueWithPointer:stat];
                    
                    [collection setValue:pointer forKey:channelName];
                }
                
                channelName = nil;
            } else if ([subgroup isEqual:GPU_PERF_STATES_SUBGROUP]) {
                NSString* channelName = @"GPUPH"; // We have no access to channel names so we can just assume the key is GPUPH on all systems
                
                stats* stat = makeStats(channelName, gpuDvfs);
                
                NSValue* pointer = [NSValue valueWithPointer:stat];
                [collection setValue:pointer forKey: channelName];
                
                channelName = nil;
            } else {
                CFArrayRemoveValueAtIndex(array, i);
            }
        }
            
        subgroup = nil;
    }
    
    // We iterate a second time to collect per core stuff. I don't know how to get channel names from these, plus
    //   they may not be in a optimal order, to just do it in the same pass, which is why we call this now.
    IOReportIterate(channel, ^int(CFDictionaryRef channel) {
        NSString* subgroup = IOReportChannelGetSubGroup(channel);
        
        if ([subgroup isNotEqualTo: CPU_CORE_PERF_STATES_SUBGROUP]) return 0;
        
        NSString* channelName = IOReportChannelGetChannelName(channel);
        NSString* parentName = [channelName substringToIndex:[channelName length] - 1];
        NSValue* value = [collection valueForKey: parentName];
        
        if (value != nil) {
            stats* parent = (stats*)[value pointerValue];
            stats* core;
            
            if ([channelName containsString:@"E"]) {
                core = makeStats(channelName, ecpuDvfs );
            } else {
                core = makeStats(channelName, pcpuDvfs );
            }

            NSValue* pointer = [NSValue valueWithPointer:core];
            
            [parent->childrenAray addObject:pointer];
            [parent->childrenDictionary setValue:pointer forKey:channelName];
            
        }
        
        channelName = nil;
        subgroup = nil;
        
        return 0;
    });
    
    return collection;
}

void update(stats* stat, CFDictionaryRef channel) {
    uint64_t idle_residency = IOReportStateGetResidency(channel, 0);
    uint64_t residencies_sum = 0;
    
    // Collect residency data
    for (int i = 1; i < stat->state_count; i++) {
        NSString* indexName = IOReportStateGetNameForIndex(channel, i);
        uint64_t residency = IOReportStateGetResidency(channel, i);
        
        if ([indexName containsString: P_STATE] || [indexName containsString: V_STATE]) {
            residencies_sum += residency;
            
            stat->pstate_distribution[i] = (float)residency;
            
        }
        
        indexName = nil;
    }
    
    // Calculate frequencies, voltages, distributions, etc. from residency data
    float freq_sum = 0;
    float mvolt_sum = 0;
    
    float multiplier = 1 / (float)residencies_sum;
    
    for (int i = 1; i < stat->state_count; i++) {
        if (residencies_sum == 0) break;
        
        NSArray* state = stat->dvfs[i];
        
        float distribtion = stat->pstate_distribution[i] * multiplier;
        float freq = distribtion * [state[0] floatValue];
        float mvolt = distribtion * [state[1] floatValue];
        
        freq_sum += freq;
        mvolt_sum += mvolt;
        
        stat->pstate_distribution[i] = distribtion;
    }
    
    // Create and return the (C/G)PU stats for all the metrics
    uint64_t complete_sum = residencies_sum + idle_residency;
    
    stat->freq = freq_sum;
    stat->mvolts = mvolt_sum;
    
    if (complete_sum != 0) {
        stat->active = ((float) residencies_sum / complete_sum) * 100;
        stat->idle = ((float) idle_residency / complete_sum) * 100;
    } else {
        stat->active = 0;
        stat->idle = 0;
    }
    
    stat->is_in_use = stat->idle != 0;
}

void updateLoop(NSMutableDictionary* collection, CFDictionaryRef sample) {
    IOReportIterate(sample, ^int(CFDictionaryRef channel) {
        NSString* subgroup = IOReportChannelGetSubGroup(channel);
        NSString* channelName = IOReportChannelGetChannelName(channel);
        
        if ([subgroup isEqual: CPU_COMPLEX_PERF_STATES_SUBGROUP] || [subgroup isEqual:GPU_PERF_STATES_SUBGROUP]) {
            NSValue* value = [collection valueForKey: channelName];
            
            if (value != nil) {
                stats* parent = (stats*)[value pointerValue];
                update(parent, channel);
            }
            
        } else if ([subgroup isEqual: CPU_CORE_PERF_STATES_SUBGROUP]) {
            NSString* parentName = [channelName substringToIndex:[channelName length] - 1];
            NSValue* value = [collection valueForKey: parentName];
            
            if (value != nil) {
                stats* parent = (stats*)[value pointerValue];
                NSValue* value = [parent->childrenDictionary valueForKey: channelName];
                
                if (value != nil) {
                    stats* core = (stats*)[value pointerValue];
                    update(core, channel);
                }
            }
        }
        
        channelName = nil;
        subgroup = nil;
        
        return 0;
    });
}

void print(NSDictionary* collection, cmd_data* cmd) {
    for (NSString* key in collection) {
        NSValue* value = [collection objectForKey: key];
        
        stats* parent = (stats*)[value pointerValue];
        
        if (([parent->name containsString:@"E"] && cmd->flags.hide_ecpu) ||
            ([parent->name containsString:@"P"] && cmd->flags.hide_pcpu) ||
            ([parent->name containsString:@"G"] && cmd->flags.hide_gpu))
        {
            continue;
        }
                
        if ([parent->name isEqualTo:@"GPUPH"]) {
            fprintf(stdout, "Integrated Graphics \n");
        } else {
            fprintf(stdout, "%ld-Core %s\n", [parent->childrenAray count], parent->name.UTF8String);
        }
        
        if (cmd->flags.show_freq) fprintf(stdout, "    Average frequency: %.0f mhz\n", parent->freq);
        if (cmd->flags.show_volts) fprintf(stdout, "    Average voltage:   %.0f mv\n", parent->mvolts);
        if (cmd->flags.show_active) fprintf(stdout, "    Active residency:  %.2f %%\n", parent->active);
        if (cmd->flags.show_idle) fprintf(stdout, "    Idle residency:    %.2f %%\n\n", parent->idle);
        
        if (cmd->flags.show_dvfs) {
            fprintf(stdout, "    DVFS distribution:\n");
            
            int counter = 0;
            
            for (int i = 0; i < parent->state_count; i++) {
                float value = parent->pstate_distribution[i] * 100;
                
                if (value > 0.009) {
                    fprintf(stdout, "        %.f MHz", [parent->dvfs[i][0] floatValue]);
                    
                    if (cmd->flags.show_dvfs_volts) fprintf(stdout, " (%.f mv)", [parent->dvfs[i][1] floatValue]);
                    
                    fprintf(stdout, ": %.2f%%\n", value);
                    
                    counter++;
                }
            }
            
            if (counter == 0) {
                fprintf(stdout, "        none");
            }
            
            printf("\n");
        }

        if (parent->childrenAray != nil && parent->childrenDictionary != nil && cmd->flags.show_percore) {
            for (int i = 0; i < [parent->childrenAray count]; i++) {
                NSValue* value = parent->childrenAray[i];
                
                stats* core = (stats*)[value pointerValue];
                
                fprintf(stdout, "    Core #%d\n", i);
                
                if (cmd->flags.show_freq) fprintf(stdout, "        Average frequency: %.0f mhz\n", core->freq);
                if (cmd->flags.show_volts) fprintf(stdout, "        Average voltage:   %.0f mv\n", core->mvolts);
                if (cmd->flags.show_active) fprintf(stdout, "        Active residency:  %.2f %%\n", core->active);
                if (cmd->flags.show_idle) fprintf(stdout, "        Idle residency:    %.2f %%\n", core->idle);
                
                if (cmd->flags.show_dvfs) {
                    fprintf(stdout, "\n        DVFS distribution:\n");
                    
                    int counter = 0;
                    
                    for (int i = 0; i < core->state_count; i++) {
                        float value = core->pstate_distribution[i] * 100;
                        
                        if (value > 0.009) {
                            fprintf(stdout, "            %.f MHz", [parent->dvfs[i][0] floatValue]);
                            
                            if (cmd->flags.show_dvfs_volts) fprintf(stdout, " (%.f mv)", [parent->dvfs[i][1] floatValue]);
                            
                            fprintf(stdout, ": %.2f%%\n", value);
                            
                            counter++;
                        }
                    }
                    
                    if (counter == 0) {
                        fprintf(stdout, "            none");
                    }
                    
                }
                
                fprintf(stdout, "\n");
            }
        }
    }
}

char* getSocName(void) {
    size_t len = 32;
    char* cpubrand = malloc(len);
    sysctlbyname("machdep.cpu.brand_string", cpubrand, &len, NULL, 0);
    
    return cpubrand;
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

static inline void init_cmd_data(cmd_data* data) {
    memset((void*)data, 0, sizeof(cmd_data));
    
    data->interval = 275;
    data->samples = 1;
    
    data->flags.show_active = true;
    data->flags.show_idle = true;
    data->flags.show_freq = true;
    data->flags.show_percore = true;
}

static void error(int exitcode, const char* format, ...) {
    va_list args;
    fprintf(stderr, "%s:\033[0;31m error:\033[0m\e[0m ", getprogname());
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fprintf(stderr, "\n");
    exit(exitcode);
}


int main(int argc, char * argv[]) {
    char* socName = getSocName();
    NSString* platformName = getPlatformName();
    
    CFMutableDictionaryRef subscriptionChannel = nil;
    CFMutableDictionaryRef cpuChannel = IOReportCopyChannelsInGroup(@"CPU Stats", nil, 0, 0, 0);
    CFMutableDictionaryRef gpuChannel = IOReportCopyChannelsInGroup(@"GPU Stats", nil, 0, 0, 0);
    IOReportMergeChannels(cpuChannel, gpuChannel, nil);
    
    CFMutableDictionaryRef channel = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(cpuChannel), cpuChannel);
    NSMutableDictionary* collection = filterChannelAndConstructCollection(channel);
    
    IOReportSubscriptionRef subscription = IOReportCreateSubscription(NULL, channel, &subscriptionChannel, 0, nil);
    
    cmd_data* cmd = malloc(sizeof(cmd_data));
    
    init_cmd_data(cmd);
    
    NSString* active_metrics_str = nil;
    NSArray* active_metrics_list = nil;
    NSString* hide_units_str = nil;
    NSArray* hide_units_list = nil;
    
    int opt = 0;
    int optindex = 0;
    
    while((opt = getopt_long(argc, argv, "hvi:s:po:m:H:wga", long_opts, &optindex)) != -1) {
        switch(opt) {
            case '?':
            case 'h':
                help();
            case 'v':
                printf("%s %s (build %s %s)\n", getprogname(), TOOL_VERSION, __DATE__, __TIME__);
                return 0;
            case 'i':
                cmd->interval = atoi(optarg);
                if (cmd->interval < 1) cmd->interval = 1;
                break;
            case 's':
                cmd->samples = atoi(optarg);
                if (cmd->samples <= 0) cmd->samples = -1;
                break;
            case 'm':
                active_metrics_str = [NSString stringWithFormat:@"%s", strdup(optarg)];
                active_metrics_list = [active_metrics_str componentsSeparatedByString:@","];
                active_metrics_str = nil;
                
                memset(&cmd->flags, 0, sizeof(cmd->flags));
                
                for (int i = 0; i < [active_metrics_list count]; i++) {
                    NSString* string = [active_metrics_list[i] lowercaseString];
                    
                    // ew, chained ifs
                    if ([string isEqual:[NSString stringWithUTF8String:METRIC_ACTIVE]])
                        cmd->flags.show_active = true;
                    else if ([string isEqual:[NSString stringWithUTF8String:METRIC_IDLE]])
                        cmd->flags.show_idle = true;
                    else if ([string isEqual:[NSString stringWithUTF8String:METRIC_FREQ]])
                        cmd->flags.show_freq = true;
                    else if ([string isEqual:[NSString stringWithUTF8String:METRIC_VOLTS]])
                        cmd->flags.show_volts = true;
                    else if ([string isEqual:[NSString stringWithUTF8String:METRIC_CORES]])
                        cmd->flags.show_percore = true;
                    else if ([string isEqual:[NSString stringWithUTF8String:METRIC_DVFS]])
                        cmd->flags.show_dvfs = true;
                    else if ([string isEqual:[NSString stringWithUTF8String:METRIC_DVFSVOLTS]])
                        cmd->flags.show_dvfs_volts = true;
//                    else if ([string isEqual:[NSString stringWithUTF8String:METRIC_POWER]])
//                        cmd->flags.show_pwr = true;
                    else
                        error(1, "Incorrect metric option \"%s\" in list", [string UTF8String]);
                }
                
                active_metrics_list = nil;
                break;
            case 'H':
                hide_units_str = [NSString stringWithFormat:@"%s", strdup(optarg)];
                hide_units_list = [hide_units_str componentsSeparatedByString:@","];
                hide_units_str = nil;
                
                for (int i = 0; i < [hide_units_list count]; i++) {
                    NSString* string = [hide_units_list[i] lowercaseString];
                    
                    if ([string isEqual:@"ecpu"]) {
                        cmd->flags.hide_ecpu = true;
                    } else if ([string isEqual:@"pcpu"]){
                        cmd->flags.hide_pcpu = true;
                    }  else if ([string isEqual:@"gpu"]) {
                        cmd->flags.hide_gpu = true;
                    } else
                        error(1, "Incorrect unit option \"%s\" in list", [string UTF8String]);
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
//                cmd->flags.show_pwr = true;
                break;
        }
    }
    
    fprintf(stdout, "Profiling %s (%s)...\n\n", socName, platformName.UTF8String);
    
    for(; cmd->samples--;) {
        CFDictionaryRef firstSample  = IOReportCreateSamples(subscription, subscriptionChannel, nil);
        
        [NSThread sleepForTimeInterval: (float)cmd->interval * 1e-3];
        
        CFDictionaryRef lastSample  = IOReportCreateSamples(subscription, subscriptionChannel, nil);
        
        CFDictionaryRef sampleDelta  = IOReportCreateSamplesDelta(firstSample, lastSample, NULL);
        
        updateLoop(collection, sampleDelta);
        
        print(collection, cmd);
        
        CFRelease(firstSample);
        CFRelease(lastSample);
        CFRelease(sampleDelta);
    }

    return 0;
}
