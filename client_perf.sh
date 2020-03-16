#!/bin/bash

###
# Store original value about system performance
###
ORIG_ASLR=$(cat /proc/sys/kernel/randomize_va_space)
ORIG_SCAL=$(cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor)
ORIG_NTURBO=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)

###
# Reduce factor of interference performance benchmark
###
echo 0 > /proc/sys/kernel/randomize_va_space
echo performance > /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo

####
# Get offset of user-space read function
####
USER_DIR=/home/kendai/git/fibdrv
READ_OFFSET=0x$(objdump -d ${USER_DIR}/client | grep 'read.*:' | sed -e 's/^0*//' -e 's/ .*//')

####
# Use ftrace to record function timestamp
####
COMMAND="$@"
DEBUG_FS=/sys/kernel/debug
CURRENT_TRACER="function"

# Enable
cat /dev/null > $DEBUG_FS/tracing/trace
echo "$CURRENT_TRACER" > $DEBUG_FS/tracing/current_tracer
echo "mono" > $DEBUG_FS/tracing/trace_clock
echo "p:user_start_time ${USER_DIR}/client:${READ_OFFSET}" >> $DEBUG_FS/tracing/uprobe_events
echo "r:user_end_time ${USER_DIR}/client:${READ_OFFSET}" >> $DEBUG_FS/tracing/uprobe_events
echo 'p:kernel_start_time fibdrv:fib_read' >> $DEBUG_FS/tracing/kprobe_events
echo 'r:kernel_end_time fibdrv:fib_read' >> $DEBUG_FS/tracing/kprobe_events
echo 'r:lseek_probe fibdrv:fib_device_lseek ret=$retval' >> $DEBUG_FS/tracing/kprobe_events
echo 1 > $DEBUG_FS/tracing/events/uprobes/enable
echo 1 > $DEBUG_FS/tracing/events/kprobes/enable
echo 1 > $DEBUG_FS/tracing/tracing_on

# Run
eval "$COMMAND"
# Stop
echo 0 > $DEBUG_FS/tracing/tracing_on
# Extract needed information
# cp $DEBUG_FS/tracing/trace $USER_DIR/trace.tmp
grep -e 'user_start_time' -e 'user_end_time' $DEBUG_FS/tracing/trace > $USER_DIR/user_time.tmp
grep -e 'kernel_start_time' -e 'kernel_end_time' $DEBUG_FS/tracing/trace > $USER_DIR/kernel_time.tmp
grep -e 'lseek_probe' $DEBUG_FS/tracing/trace > $USER_DIR/lseek_offset.tmp

# Disable
echo 0 > $DEBUG_FS/tracing/events/kprobes/enable
echo 0 > $DEBUG_FS/tracing/events/uprobes/enable
echo "local" > $DEBUG_FS/tracing/trace_clock
echo '-:lseek_probe' >> $DEBUG_FS/tracing/kprobe_events
echo '-:kernel_end_time' >> $DEBUG_FS/tracing/kprobe_events
echo '-:kernel_start_time' >> $DEBUG_FS/tracing/kprobe_events
echo '-:user_end_time' >> $DEBUG_FS/tracing/uprobe_events
echo '-:user_start_time' >> $DEBUG_FS/tracing/uprobe_events
echo 'nop' > $DEBUG_FS/tracing/current_tracer
cat /dev/null > $DEBUG_FS/tracing/trace

####
# Calculate user & kernel function duration
####
rm -f $USER_DIR/client_time

cnt=1
while [ $cnt -le 100 ] && IFS=" " read -r -u 4 user1 && IFS=" " read -r -u 5 kernel1 && IFS=" " read -r -u 6 lseek; do
    ((cnt++))
    read -r -u 4 user2
    read -r -u 5 kernel2

    ustart=$(echo $user1 | cut -d " " -f 4 | sed 's/.$//')
    uend=$(echo $user2 | cut -d " " -f 4 | sed 's/.$//')
    kstart=$(echo $kernel1 | cut -d " " -f 4 | sed 's/.$//')
    kend=$(echo $kernel2 | cut -d " " -f 4 | sed 's/.$//')
    offset=$(echo $lseek | cut -d " " -f 9 | sed 's/^[a-z0-9]*=//')

    utime=$(echo "scale=6; ($uend-$ustart)*1000000" | bc | sed 's/.[0]*$//')
    ktime=$(echo "scale=6; ($kend-$kstart)*1000000" | bc | sed 's/.[0]*$//')

    echo "$(($offset)) $utime $ktime" >> $USER_DIR/client_time
done 4<$USER_DIR/user_time.tmp 5<$USER_DIR/kernel_time.tmp 6<$USER_DIR/lseek_offset.tmp

rm *.tmp

###
# Restore value about system performance
###
echo "$ORIG_ASLR" > /proc/sys/kernel/randomize_va_space
echo "$ORIG_SCAL" > /sys/devices/system/cpu/cpu7/cpufreq/scaling_governor
echo "$ORIG_NTURBO" > /sys/devices/system/cpu/intel_pstate/no_turbo
