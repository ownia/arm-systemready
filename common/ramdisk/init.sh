#!/bin/sh

# @file
# Copyright (c) 2021-2024, Arm Limited or its affiliates. All rights reserved.
# SPDX-License-Identifier : Apache-2.0

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#Mount things needed by this script
/bin/busybox mount -t proc proc /proc

#softlink current console to /dev/tty for ssh/scp utility
rm /dev/tty
ln -s $(tty) /dev/tty

if ! mountpoint -q /sys; then
        echo "Mounting /sysfs..."
        /bin/busybox mount -t sysfs sysfs /sys
else
        echo "/sysfs is already mounted."
fi

mount -t efivarfs efivarfs /sys/firmware/efi/efivars
echo "init.sh"

#Create a link of S99init.sh to init.sh
if [ ! -f /init.sh ]; then
 ln -s  /etc/init.d/S99init.sh /init.sh
fi

#Create all the symlinks to /bin/busybox
/bin/busybox --install -s


#give linux time to finish initlazing disks
sleep 5
mdev -s

echo "Starting disk drivers"
insmod /lib/modules/xhci-pci-renesas.ko
insmod /lib/modules/xhci-pci.ko
insmod /lib/modules/nvme-core.ko
insmod /lib/modules/nvme.ko

sleep 5

#Skip running of ACS Tests if the grub option is added
ADDITIONAL_CMD_OPTION="";
ADDITIONAL_CMD_OPTION=`cat /proc/cmdline | awk '{ print $NF}'`

if [ $ADDITIONAL_CMD_OPTION != "noacs" ]; then
 #mount result partition
 BLOCK_DEVICE_NAME=$(blkid | grep "BOOT_ACS" | awk -F: '{print $1}')

 if [ ! -z "$BLOCK_DEVICE_NAME" ]; then
  mount $BLOCK_DEVICE_NAME /mnt
  echo "Mounted the results partition on device $BLOCK_DEVICE_NAME"
 else
  echo "Warning: the results partition could not be mounted. Logs may not be saved correctly"
 fi

 if [ $ADDITIONAL_CMD_OPTION == "secureboot" ]; then
  echo "Call SIE ACS"
  /usr/bin/secure_init.sh
  echo "SIE ACS run is completed\n"
  echo "Please press <Enter> to continue ..."
  sync /mnt
  sleep 3
  exec sh +m
 fi

 if [ $ADDITIONAL_CMD_OPTION == "acsforcevamap" ]; then
  echo "Linux Boot with SetVirtualMap enabled"
  mkdir -p /mnt/acs_results/SetVAMapMode/fwts
  echo "Executing FWTS"
  fwts  -r stdout -q --uefi-set-var-multiple=1 --uefi-get-mn-count-multiple=1 --sbbr esrt uefibootpath aest cedt slit srat hmat pcct pdtt bgrt bert einj erst hest sdei nfit iort mpam ibft ras2 > /mnt/acs_results/SetVAMapMode/fwts/FWTSResults.log
  sync /mnt
  sleep 3
  echo "The ACS test suites are completed."
  exec sh +m
 fi

 #linux debug dump
 mkdir -p /mnt/acs_results/linux_dump
 dmesg > /mnt/acs_results/linux_dump/dmesg.log
 lspci > /mnt/acs_results/linux_dump/lspci.log
 lspci -vvv &> /mnt/acs_results/linux_dump/lspci-vvv.log
 cat /proc/interrupts > /mnt/acs_results/linux_dump/interrupts.log
 cat /proc/cpuinfo > /mnt/acs_results/linux_dump/cpuinfo.log
 cat /proc/meminfo > /mnt/acs_results/linux_dump/meminfo.log
 cat /proc/iomem > /mnt/acs_results/linux_dump/iomem.log
 lscpu > /mnt/acs_results/linux_dump/lscpu.log
 lsblk > /mnt/acs_results/linux_dump/lsblk.log
 lsusb > /mnt/acs_results/linux_dump/lsusb.log
 dmidecode > /mnt/acs_results/linux_dump/dmidecode.log
 dmidecode --dump-bin /mnt/acs_results/linux_dump/dmidecode.bin
 uname -a > /mnt/acs_results/linux_dump/uname.log
 cat /etc/os-release > /mnt/acs_results/linux_dump/cat-etc-os-release.log
 date > /mnt/acs_results/linux_dump/date.log
 cat /proc/driver/rtc > /mnt/acs_results/linux_dump/rtc.log
 hwclock > /mnt/acs_results/linux_dump/hwclock.log
 efibootmgr > /mnt/acs_results/linux_dump/efibootmgr.log
 efibootmgr -t 20 > /mnt/acs_results/linux_dump/efibootmgr-t-20.log
 efibootmgr -t 5 > /mnt/acs_results/linux_dump/efibootmgr-t-5.log
 efibootmgr -c > /mnt/acs_results/linux_dump/efibootmgr-c.txt
 ifconfig > /mnt/acs_results/linux_dump/ifconfig.log
 ip addr show > /mnt/acs_results/linux_dump/ip-addr-show.log
 ping -c 5 www.arm.com > /mnt/acs_results/linux_dump/ping-c-5-www-arm-com.log
 acpidump > /mnt/acs_results/linux_dump/acpi.log
 acpixtract -a >> /mnt/acs_results/linux_dump/acpi.log
 iasl -d /mnt/acs_results/linux_dump/*.dat
 date --set="20221215 05:30" > /mnt/acs_results/linux_dump/date-set-202212150530.log
 date > /mnt/acs_results/linux_dump/date-after-set.log
 hwclock --set --date "2023-01-01 09:10:15" > /mnt/acs_results/linux_dump/hw-clock-set-20230101091015.log
 hwclock > /mnt/acs_results/linux_dump/hwclock-after-set.log
 ls -lR /sys/firmware > /mnt/acs_results/linux_dump/firmware.log
 cp -r /sys/firmware /mnt/acs_results/linux_dump/

#Go through linux_dump and uefi_dump to retrieve hardware/device/driver failures/errors/faults
LOG_FILE="/mnt/acs_results/sniff_test_debugdump_$(date +%Y%m%d_%H%M%S).log"
PARENT_DIR="/mnt/acs_results"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${GREEN}Finding hardware, driver, and device errors...${NC}"
echo -e "${YELLOW}Hardware/Device/Firmware errors and warnings from Linux and UEFI dump:${NC}" >> $LOG_FILE
grep -rnEi '(error|fail|fault).*?(hardware|hw|driver|device|firmware|pcie|usb)' \
    $(find "$PARENT_DIR"/linux_dump -type f ! -name 'dmesg.log') \
    "$PARENT_DIR"/uefi_dump >> $LOG_FILE
echo -e "${YELLOW}All other errors and warnings from Linux and UEFI dump:${NC}" >> $LOG_FILE
grep -rnEi '(error|fail|fault)' \
    $(find "$PARENT_DIR"/linux_dump -type f ! -name 'dmesg.log') \
    "$PARENT_DIR"/uefi_dump >> $LOG_FILE
if [ $(wc -l < "$LOG_FILE") -gt 1 ]; then
    echo -e "${GREEN}Hardware/Device/Firmware error summary saved to $LOG_FILE${NC}. Please review the logs manually."
    cat $LOG_FILE
else
    echo -e "${GREEN}No device/driver errors or faults were found in linux_dump (excluding dmesg.log) and uefi_dump. Please review the logs manually.${NC}"
    echo -e "No device/driver errors or faults were found in linux_dump (excluding dmesg.log) and uefi_dump. Please review the logs manually." >> $LOG_FILE
fi

#Go through dmesg to retrieve hardware/device/driver failures/errors/faults
DMESG_FILE="/mnt/acs_results/linux_dump/dmesg.log"
LOG_FILE="/mnt/acs_results/sniff_test_dmesg_$(date +%Y%m%d_%H%M%S).log"
echo -e "${YELLOW}Hardware/Device/Firmware errors and warnings from dmesg:${NC}" >> $LOG_FILE
grep -nEi '(error|fail|fault).*?(hardware|hw|driver|device|firmware|pcie|usb)' "$DMESG_FILE" >> $LOG_FILE
echo -e "${YELLOW}All other errors and warnings from dmesg:${NC}" >> $LOG_FILE
grep -nEi '(error|fail| fault)' "$DMESG_FILE" >> $LOG_FILE
if [ $(wc -l < "$LOG_FILE") -gt 1 ]; then
    echo -e "${GREEN}Hardware/Device/Firmware error summary saved to $LOG_FILE$. Please review the logs manually.{NC}"
    cat $LOG_FILE
else
    echo -e "${GREEN}No device/driver errors or faults were found in dmesg.log. Please review the logs manually.${NC}"
    echo -e "No device/driver errors or faults were found in dmesg.log. Please review the logs manually." >> $LOG_FILE
fi

 mkdir -p /mnt/acs_results/fwts

 #Check for the existense of fwts test configuration file in the package. EBBR Execution
 if [ -f  /bin/ir_bbr_fwts_tests.ini ]; then
  test_list=`cat /bin/ir_bbr_fwts_tests.ini | grep -v "^#" | awk '{print $1}' | xargs`
  echo "Test Executed are $test_list"
  fwts `echo $test_list` -f -r /mnt/acs_results/fwts/FWTSResults.log
 else
  #SBBR Execution
  echo "Executing FWTS for SBBR"
  echo $'SystemReady SR ACS v2.1.0 \nFWTS v24.01.00' > /mnt/acs_results/fwts/FWTSResults.log
  fwts  -r stdout -q --uefi-set-var-multiple=1 --uefi-get-mn-count-multiple=1 --sbbr esrt uefibootpath aest cedt slit srat hmat pcct pdtt bgrt bert einj erst hest sdei nfit iort mpam ibft ras2 > /mnt/acs_results/fwts/FWTSResults.log
 fi

 sleep 2

 if [ ! -f  /bin/ir_bbr_fwts_tests.ini ]; then
  #Run Linux BSA tests for ES and SR only
  mkdir -p /mnt/acs_results/linux
  sleep 3
  echo "Running Linux BSA tests"
  if [ -f  /lib/modules/bsa_acs.ko ]; then
   #Case of ES
   insmod /lib/modules/bsa_acs.ko
   if [ -f /bin/sr_bsa.flag ]; then
    echo $'SystemReady SR ACS v2.1.0\n' > /mnt/acs_results/linux/BsaResultsApp.log
   else
    echo $'SystemReady ES ACS v1.4.0\n' > /mnt/acs_results/linux/BsaResultsApp.log
   fi
   /bin/bsa >> /mnt/acs_results/linux/BsaResultsApp.log
   dmesg | sed -n 'H; /PE_INFO/h; ${g;p;}' > /mnt/acs_results/linux/BsaResultsKernel.log
  else
   echo "Error: BSA kernel Driver is not found. Linux BSA tests cannot be run."
  fi

  if [ -f /bin/sr_bsa.flag ]; then
   echo "Running Linux SBSA tests"
   if [ -f  /lib/modules/sbsa_acs.ko ]; then
    #Case of SR
    insmod /lib/modules/sbsa_acs.ko
    echo $'SystemReady SR ACS v2.1.0\n' > /mnt/acs_results/linux/SbsaResultsApp.log
    /bin/sbsa >> /mnt/acs_results/linux/SbsaResultsApp.log
    dmesg | sed -n 'H; /PE_INFO/h; ${g;p;}' > /mnt/acs_results/linux/SbsaResultsKernel.log
   else
    echo "Error: SBSA kernel Driver is not found. Linux SBSA tests cannot be run."
   fi
  fi
 fi
 if [ -d "/mnt/acs_results/sct_results" ]; then
     echo "Running edk2-test-parser tool "
     mkdir -p /mnt/acs_results/edk2-test-parser
     cd /usr/bin/edk2-test-parser
     ./parser.py --md /mnt/acs_results/edk2-test-parser/edk2-test-parser.log /mnt/acs_results/sct_results/Overall/Summary.ekl /mnt/acs_results/sct_results/Sequence/SBBR.seq > /dev/null 2>&1
 else
     echo "SCT result does not exist, cannot run edk2-test-parser tool cannot run"
 fi
 echo "The ACS test suites are completed."
else
 echo ""
 echo "Additional option set to not run ACS Tests. Skipping ACS tests on Linux"
 echo ""
fi

sync /mnt
sleep 3

exec sh +m
