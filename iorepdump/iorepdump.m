//
//  iorepdump.m
//  socpwrbud (iorepdump)
//
//  Copyright (c) 2023 dehydratedpotato.
//

#import <Foundation/Foundation.h>
#import <sys/sysctl.h>

typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;

extern IOReportSubscriptionRef IOReportCreateSubscription(void *, /* NULL */
                                                          CFMutableDictionaryRef desiredChannels,
                                                          CFMutableDictionaryRef *subbedChannels,
                                                          uint64_t               channel_id,/* 0 */
                                                          CFTypeRef /* nil */);

extern void IOReportIterate(CFDictionaryRef samples, int (^)(CFDictionaryRef channel));

extern CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef subscription,
                                             CFMutableDictionaryRef  subbedChannels,
                                             CFTypeRef /* nil */);

extern NSString * IOReportChannelGetChannelName(CFDictionaryRef);
extern NSString * IOReportChannelGetGroup(CFDictionaryRef);
extern NSString * IOReportChannelGetSubGroup(CFDictionaryRef);

extern int IOReportStateGetCount(CFDictionaryRef);
extern uint64_t IOReportStateGetResidency(CFDictionaryRef, int);
extern NSString * IOReportStateGetNameForIndex(CFDictionaryRef, int);
extern uint64_t IOReportArrayGetValueAtIndex(CFDictionaryRef, int);
extern long IOReportSimpleGetIntegerValue(CFDictionaryRef, int);

extern CFMutableDictionaryRef IOReportCopyAllChannels(uint64_t, uint64_t);
extern int IOReportChannelGetFormat(CFDictionaryRef samples);

enum {
    kIOReportInvalidFormat     = 0,
    kIOReportFormatSimple      = 1,
    kIOReportFormatState       = 2,
    kIOReportFormatSimpleArray = 4
};

NSString * getcpu(void) {
    size_t len = 32;
    char *cpubrand = malloc(len);

    sysctlbyname("machdep.cpu.brand_string", cpubrand, &len, NULL, 0);

    NSString *ret = [NSString stringWithFormat:@"%s", cpubrand, nil];
    free(cpubrand);

    return ret;
}

int main(int argc, char *argv[]) {
    @autoreleasepool
    {
        NSString *cpu = getcpu();
        int clusters = 2;

        if (([cpu rangeOfString:@"Pro"].location != NSNotFound) ||
            ([cpu rangeOfString:@"Max"].location != NSNotFound)) {
            clusters = 3;
        } else if ([cpu rangeOfString:@"Ultra"].location != NSNotFound) {
            clusters = 6;
        }

        CFMutableDictionaryRef subchn = NULL;
        CFMutableDictionaryRef chn = IOReportCopyAllChannels(0, 0);
        IOReportSubscriptionRef sub = IOReportCreateSubscription(NULL, chn, &subchn, 0, 0);

        IOReportIterate(IOReportCreateSamples(sub, subchn, NULL), ^int (CFDictionaryRef sample) {
            NSString *group = IOReportChannelGetGroup(sample);
            NSString *subgroup = IOReportChannelGetSubGroup(sample);
            NSString *chann_name = IOReportChannelGetChannelName(sample);

            if ([group isEqual:@"CPU Stats"]  ||
                [group isEqual:@"GPU Stats"]  ||
                [group isEqual:@"AMC Stats"]  ||
                [group isEqual:@"CLPC Stats"] ||
                [group isEqual:@"PMP"]        ||
                [group isEqual:@"Energy Model"]) {
                switch (IOReportChannelGetFormat(sample)) {
                    case kIOReportFormatSimple:
                        printf("Grp: %s   Subgrp: %s   Chn: %s   Int: %ld\n", [group UTF8String], [subgroup UTF8String], [chann_name UTF8String], IOReportSimpleGetIntegerValue(sample, 0));
                        break;

                    case kIOReportFormatState:

                        for (int i = 0; i < IOReportStateGetCount(sample); i++) {
                            printf("Grp: %s   Subgrp: %s   Chn: %s   State: %s   Res: %lld\n", [group UTF8String], [subgroup UTF8String], [chann_name UTF8String], [IOReportStateGetNameForIndex(sample, i) UTF8String], IOReportStateGetResidency(sample, i));
                        }

                        break;

                    case kIOReportFormatSimpleArray:

                        for (int i = 0; i < clusters; i++) {
                            printf("Grp: %s   Subgrp: %s   Chn: %s   Arr: %lld\n", [group UTF8String], [subgroup UTF8String], [chann_name UTF8String], IOReportArrayGetValueAtIndex(sample, i));
                        }

                        break;
                }
            }

            return 0;
        });

        return 0;
    }
}
