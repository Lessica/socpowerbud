
<h1>
    socpowerbud
    <a href="https://github.com/dehydratedpotato/socpowerbud/releases">
        <img alt="Releases" src="https://img.shields.io/github/release/BitesPotatoBacks/SocPowerBuddy.svg"/>
    </a>
<!--     <a href="">
       <img alt="Platform" src="https://img.shields.io/badge/platform-macOS-lightgray.svg"/>
    </a> -->
    <a href="https://github.com/dehydratedpotato/socpowerbud/blob/main/LICENSE">
        <img alt="License" src="https://img.shields.io/github/license/BitesPotatoBacks/SocPowerBuddy.svg"/>
    </a>
    <a href="https://github.com/dehydratedpotato/socpowerbud/stargazers">
        <img alt="Stars" src="https://img.shields.io/github/stars/BitesPotatoBacks/SocPowerBuddy.svg"/>
    </a>
</h1>

Sudoless utility to profile average frequency, voltage, residency, and more on Apple Silicon!

- **Table of contents**
  - **[Project Deets](#project-deets)**
  - **[Example Output](#example-output)**
  - [Features](#features)
  - **[Installation, Usage, and Making](#installation-usage-and-making)**
    - [Install using Homebrew](#install-using-homebrew)
    - [Install manually](#install-manually)
    - [Building yourself](#building-yourself)
  - [Outside Influence](#outside-influence)
  - [Compatibility Notes](#compatibility-notes)
  - [Contribution](#contribution)

___

## Project Deets
This tool samples counter values from the IOReport and returns formatted results for various metrics. It's written in Objective-C because NS types made things easier, but it's starting to get all mixed around and junk from a bunch of half-refactoring...At least it's getting more effecient over time or something? Idk. Activity on this project is kind of random. Ive got other things in life to do so fixes may be a bit slow.

It is based on reverse engineering `powermetrics`, and reports pretty much every statistic offered by `powermetrics -s cpu_power,gpu_power`, plus some extras here and there (see [full metric list](#features) and [example output](#example))... but it doesn't need `sudo` to run. Because, uh, needing to be system admin in order to monitor Apple Silicon frequencies is dumb (yeah, I'm looking at you, `powermetrics`). So here you go! No administrative privileges needed! Yaaay.

### Example Output
**Note:** The following is a complete output of `socpwrbud -a` running on a M2 Pro 16" Macbook Pro.
<details>

<summary>Expand Example to see...warning, it's a large one</summary>

```
Profiling Apple M3 Pro (T6030)...

Integrated Graphics 
    Average frequency: 609 mhz
    Average voltage:   692 mv
    Active residency:  2.46 %
    Idle residency:    97.54 %

    DVFS distribution:
        338 MHz (655 mv): 46.49%
        796 MHz (715 mv): 33.53%
        924 MHz (740 mv): 19.98%

6-Core ECPU
    Average frequency: 2079 mhz
    Average voltage:   957 mv
    Active residency:  28.44 %
    Idle residency:    71.56 %

    DVFS distribution:
        744 MHz (790 mv): 33.40%
        2748 MHz (1040 mv): 66.60%

    Core #0
        Average frequency: 2110 mhz
        Average voltage:   960 mv
        Active residency:  19.12 %
        Idle residency:    80.88 %

        DVFS distribution:
            744 MHz (790 mv): 31.84%
            2748 MHz (1040 mv): 68.16%

    Core #1
        Average frequency: 2171 mhz
        Average voltage:   968 mv
        Active residency:  9.73 %
        Idle residency:    90.27 %

        DVFS distribution:
            744 MHz (790 mv): 28.79%
            2748 MHz (1040 mv): 71.21%

    Core #2
        Average frequency: 1808 mhz
        Average voltage:   923 mv
        Active residency:  8.90 %
        Idle residency:    91.10 %

        DVFS distribution:
            744 MHz (790 mv): 46.89%
            2748 MHz (1040 mv): 53.11%

    Core #3
        Average frequency: 1920 mhz
        Average voltage:   937 mv
        Active residency:  2.83 %
        Idle residency:    97.17 %

        DVFS distribution:
            744 MHz (790 mv): 41.30%
            2748 MHz (1040 mv): 58.70%

    Core #4
        Average frequency: 2038 mhz
        Average voltage:   951 mv
        Active residency:  2.01 %
        Idle residency:    97.99 %

        DVFS distribution:
            744 MHz (790 mv): 35.43%
            2748 MHz (1040 mv): 64.57%

    Core #5
        Average frequency: 2061 mhz
        Average voltage:   954 mv
        Active residency:  1.13 %
        Idle residency:    98.87 %

        DVFS distribution:
            744 MHz (790 mv): 34.27%
            2748 MHz (1040 mv): 65.73%

6-Core PCPU
    Average frequency: 2057 mhz
    Average voltage:   897 mv
    Active residency:  12.09 %
    Idle residency:    87.91 %

    DVFS distribution:
        696 MHz (790 mv): 42.27%
        2424 MHz (890 mv): 1.65%
        2988 MHz (960 mv): 49.49%
        3420 MHz (1090 mv): 3.64%
        4056 MHz (1150 mv): 2.94%

    Core #0
        Average frequency: 2033 mhz
        Average voltage:   890 mv
        Active residency:  4.61 %
        Idle residency:    95.39 %

        DVFS distribution:
            696 MHz (790 mv): 41.27%
            2424 MHz (890 mv): 2.99%
            2988 MHz (960 mv): 53.91%
            3420 MHz (1090 mv): 1.81%
            4056 MHz (1150 mv): 0.01%

    Core #1
        Average frequency: 1974 mhz
        Average voltage:   889 mv
        Active residency:  7.62 %
        Idle residency:    92.38 %

        DVFS distribution:
            696 MHz (790 mv): 44.88%
            2424 MHz (890 mv): 1.23%
            2988 MHz (960 mv): 49.61%
            3420 MHz (1090 mv): 3.78%
            4056 MHz (1150 mv): 0.50%

    Core #2
        Average frequency: 3122 mhz
        Average voltage:   1031 mv
        Active residency:  0.20 %
        Idle residency:    99.80 %

        DVFS distribution:
            696 MHz (790 mv): 5.59%
            2424 MHz (890 mv): 1.67%
            2988 MHz (960 mv): 30.18%
            3420 MHz (1090 mv): 62.37%
            4056 MHz (1150 mv): 0.19%

    Core #3
        Average frequency: 4006 mhz
        Average voltage:   1141 mv
        Active residency:  0.35 %
        Idle residency:    99.65 %

        DVFS distribution:
            2988 MHz (960 mv): 4.69%
            4056 MHz (1150 mv): 95.31%

    Core #4
        Average frequency: 0 mhz
        Average voltage:   0 mv
        Active residency:  0.00 %
        Idle residency:    100.00 %

        DVFS distribution:

    Core #5
        Average frequency: 3228 mhz
        Average voltage:   1032 mv
        Active residency:  0.04 %
        Idle residency:    99.96 %

        DVFS distribution:
            2988 MHz (960 mv): 44.42%
            3420 MHz (1090 mv): 55.58%
```

</details>

# Features

The following metrics are available sampled unit per-cluster:
- Active and Idle Residencies
- Active Frequencies and Voltage
- DVFS Distribution 
- ~~Power Consumption~~ (missing for now)
- ~~Micro architecture names~~ (missing for now)

Per-core metrics of the same are available for the CPUs.

I would love to support ANE stuff, there are remnants in `powermetrics` for gettig that data, but no real keys in IOReport for them. 

# Installation, Usage, and Making
**Note:** Tool usage is listed by `socpwrbud -h`, or `--help` if you're a verbose kinda person.

### Install using Homebrew
Let me get back to you on that. 

<!--
1. If you dont have Hombrew, then what the heck? [Install it already, geez](https://brew.sh/index_ko).
2. Add my tap using `brew tap dehydratedpotato/tap`
3. Install the tool with `brew install socpwrbud`
4. Run `socpwrbud`! (dont ask why "power" is shortened for the binary name)
-->

### Install manually
1. Download the bin from [latest release](https://github.com/dehydratedpotato/socpowerbud/releases).
2. Unzip the downloaded file into your desired dir (such as `/usr/bin`) 
4. Run `socpwrbud`! (still, dont ask why "power" is shortened for the binary name)

### Building yourself
Xcode proj is in source but you can build with `make` if you so desire...
___

## Outside Influence
This project managed to reach influence into the IOReport related metric gathering on [NeoAsitop](https://github.com/op06072/NeoAsitop).

## Compatibility Notes
I'll try to get a better up to date table here some day in time, maybe. Apple breaks stuff a lot so I can't confirm anything. M1, M2, M3, M3 pro should work fine at least. It's usually Max and Ultras that have problem, or at least a chip with more than 1 cluster per CPU type in it.


## Contribution
If any bugs or issues are found, please let me know in the [issues](https://github.com/dehydratedpotato/socpowerbud/issues) section. If the problem is related to missing IOReport entries, please share the output of the `iorepdump` tool found in the [latest release](https://github.com/dehydratedpotato/socpowerbud/releases/latest). Feel free to open a PR if you know what you're doing :smile:




