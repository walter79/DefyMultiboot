run_script()
{
  logd "running script $1..."
  chmod 0755 $1
  $1
}

fshook_pathsetup()
{
  logd "setup paths..."
  ### specify paths	
	# set global var for partition
	setenv FSHOOK_CONFIG_PARTITION $MC_DEFAULT_PARTITION
	setenv FSHOOK_CONFIG_PATH $MC_DEFAULT_PATH
	
	# mount partition which contains fs-image
  logd "mounting imageSrc-partition..."
  mkdir -p $FSHOOK_PATH_MOUNT_IMAGESRC
  mount -o rw $FSHOOK_CONFIG_PARTITION $FSHOOK_PATH_MOUNT_IMAGESRC
	
	# check for bypass-file
	if [ -f $FSHOOK_PATH_MOUNT_CACHE/multiboot/.bypass ];then
	   logi "Bypass GUI!"
	   bypass_data=`cat $FSHOOK_PATH_MOUNT_CACHE/multiboot/.bypass`
	   result_mode=`echo $bypass_data | cut -d':' -f1`
	   result_name=`echo $bypass_data | cut -d':' -f2`
	   rm -f $FSHOOK_PATH_MOUNT_CACHE/multiboot/.bypass
	   
  else
   	 # generate args for GUI
	   logd "search for virtual systems..."
	   args=""
	   for file in $FSHOOK_PATH_MOUNT_IMAGESRC$FSHOOK_CONFIG_PATH/*; do
	     if [ -d $file ]; then
	       logd "found $file!"
	       name=`basename $file`
	       args="$args$name "
	     fi
	   done
	  
	   # get fshook_folder from GUI
	   logi "starting GUI..."
	   result=`/system/bootmenu/binary/multiboot $args`
	   logd "GUI returned: $result"
	   logd "parsing results of GUI..."
	   result_mode=`echo $result |cut -d' ' -f1`
	   result_name=`echo $result |cut -d' ' -f2`
  fi
	
  # set 2nd argument as fshook_folder
  if [ -n $result_name ]; then
    
    # set global var for path to virtual system
    setenv FSHOOK_CONFIG_VS "$FSHOOK_CONFIG_PATH/$result_name"
  
    logd "virtual system: $FSHOOK_CONFIG_VS"
  fi
  
  logd "path-setup done!"
}

fshook_init()
{
  logi "Initializing..."
  
  # mount ramdisk rw
  logd "mounting ramdisk rw..."
  mount -o remount,rw /
 
  # copy fshook-files to ramdisk so we can access it while system is unmounted
  logd "copy multiboot-files to ramdisk..."
  mkdir -p $FSHOOK_PATH_RD_FILES
  cp -f $FSHOOK_PATH_INSTALLATION/* $FSHOOK_PATH_RD_FILES
  cp -f /system/bootmenu/script/_config.sh $FSHOOK_PATH_RD_FILES/

  # mount original data-partition
  logd "mounting data-partition..."
  mkdir -p $FSHOOK_PATH_MOUNT_DATA
  mount -o rw $PART_DATA $FSHOOK_PATH_MOUNT_DATA
  
  # mount original cache-partition
  logd "mounting cache-partition..."
  mkdir -p $FSHOOK_PATH_MOUNT_CACHE
  mount -o rw $PART_CACHE $FSHOOK_PATH_MOUNT_CACHE
  
  # setup paths(already mounts fsimage-partition)
  fshook_pathsetup
  bootmode=$result_mode
  logi "bootmode: $bootmode"
  
  # parse bootmode
  if [ "$bootmode" = "bootvirtual" ];then
   logi "Booting virtual system..."
   #checkKernel
  elif [ "$bootmode" = "bootnand" ];then
   logi "Booting from NAND..."
   cleanup
   logd "run 2nd-init..."
   $BM_ROOTDIR/script/2nd-init.sh
   exit $?
  elif [ "$bootmode" = "recovery" ];then
   logi "Booting recovery for virtual system..."
   source $FSHOOK_PATH_RD_FILES/fshook.bootrecovery.sh
   exit 1
  elif [ "$bootmode" = "nandrecovery" ];then
   logi "Booting recovery for NAND-system..."
   cleanup
   $BM_ROOTDIR/script/recovery_stable.sh
   exit $?
  else
   throwError
  fi
}

checkKernel()
{
   # check if flasher is enabled
   if [ ! $MC_ENABLE_BOOTFLASHER ];then
      logi "Bootflasher is disabled!"
      return
   fi
   
   # stop here if the important files are missing
   logd "Checking for files..."
   if [ ! -f $FSHOOK_PATH_MOUNT_IMAGESRC$FSHOOK_CONFIG_VS/.nand/boot.img ];then throwError;fi
   if [ ! -f $FSHOOK_PATH_MOUNT_IMAGESRC$FSHOOK_CONFIG_VS/.nand/devtree.img ];then throwError;fi
   if [ ! -f $FSHOOK_PATH_MOUNT_IMAGESRC$FSHOOK_CONFIG_VS/.nand/logo.img ];then throwError;fi
   
   # calculate md5sums
   logd "Calculating md5sum of boot-partition..."
   md5_nand=`md5sum /dev/block/boot | cut -d' ' -f1`
   errorCheck
   logd "Calculating md5sum of boot.img..."
   md5_virtual=`md5sum $FSHOOK_PATH_MOUNT_IMAGESRC$FSHOOK_CONFIG_VS/.nand/boot.img | cut -d' ' -f1`
   errorCheck
   
   # stop here if VS's md5sum is unknown
   logd "Compare md5sum of boot.img with database..."
   if [ "$md5_virtual" != "f75ffab7f0bf66235b697ccc90db623e" -a "$md5_virtual" != "b085ebd898a3a33de3a96e0e11ac8eca" ];then
      throwError
   fi
   
   # compare md5sums
   logd "Compare boot-partition with boot.img..."
   if [ "$md5_nand" != "$md5_virtual" ];then
      logi "Flashing VS's partitions..."
      
      # flash VS's partition's
		  dd if=$FSHOOK_PATH_MOUNT_IMAGESRC$FSHOOK_CONFIG_VS/.nand/boot.img of=/dev/block/boot
		  dd if=$FSHOOK_PATH_MOUNT_IMAGESRC$FSHOOK_CONFIG_VS/.nand/devtree.img of=/dev/block/mmcblk1p12
		  dd if=$FSHOOK_PATH_MOUNT_IMAGESRC$FSHOOK_CONFIG_VS/.nand/logo.img of=/dev/block/mmcblk1p10
		  
		  # reboot
      echo "bootvirtual:$result_name" > $FSHOOK_PATH_MOUNT_CACHE/multiboot/.bypass
      reboot
	 else
		  logi "NAND already uses same partitions like VS."
	 fi
}

cleanup()
{
   logd "undo changes..."
   umount $FSHOOK_PATH_MOUNT_IMAGESRC
   errorCheck
   umount $FSHOOK_PATH_MOUNT_CACHE
   errorCheck
   umount $FSHOOK_PATH_MOUNT_DATA
   errorCheck
   rm -rf $FSHOOK_PATH_RD
}

move_system()
{
  logd "moving system-partition into fshook-folder"
  # move original system-partition to fshook-environment
  mkdir -p $FSHOOK_PATH_MOUNT_SYSTEM
  mount -o move /system $FSHOOK_PATH_MOUNT_SYSTEM
  errorCheck
}

patch_initrc()
{
  logd "patching init.rc..."
  cp -f $FSHOOK_PATH_RD_FILES/init.hook.rc /init.mapphone_umts.rc
  cat /system/bootmenu/2nd-init/init.mapphone_umts.rc >> /init.mapphone_umts.rc
  errorCheck
} 

prevent_system_unmount()
{
  logd "locking unmount of system-partition..."
  cp $FSHOOK_PATH_RD_FILES/fshook.prevent_unmount.sh /system/fshook.prevent_unmount.sh
  chmod 0755 /system/fshook.prevent_unmount.sh
  /system/fshook.prevent_unmount.sh&
}

prevent_system_unmount_cleanup()
{
  logd "cleanup unmount-lock..."
  rm /system/fshook.prevent_unmount.sh
}

createLoopDevice()
{
  if [ ! -f /dev/block/loop$1 ]; then
	  # create new loop-device
	  mknod -m 0600 /dev/block/loop$1 b 7 $1
	  chown root.root /dev/block/loop$1
  fi
}

replacePartition()
{
  PARTITION_NODE=$1
  FILENAME=$2
  LOOPID=$3
  logd "Replacing partition $PARTITION_NODE with loop$LOOPID with image '$FILENAME'..."
  
  # setup loop-device with new image
  createLoopDevice $LOOPID
  losetup /dev/block/loop$LOOPID $FSHOOK_PATH_MOUNT_IMAGESRC/$FILENAME
  errorCheck
  
  # replace partition with loop-node
  rm -f $PARTITION_NODE
  mknod -m 0600 $PARTITION_NODE b 7 $LOOPID
  errorCheck
}

throwError()
{
    # turn off led's
    echo 0 > /sys/class/leds/red/brightness
    echo 0 > /sys/class/leds/green/brightness
    echo 0 > /sys/class/leds/blue/brightness

    # let red led blink two times
    echo 1 > /sys/class/leds/red/brightness
    sleep 1
    echo 0 > /sys/class/leds/red/brightness
    sleep 1
    echo 1 > /sys/class/leds/red/brightness
    sleep 1
    echo 0 > /sys/class/leds/red/brightness

    # exit
    loge "Error: $1"
    if [ $fshookstatus == "init" ]; then
      exit $1
    else
      reboot
    fi
}

errorCheck()
{
  exitcode=$?
  if [ "$exitcode" -ne "0" ]; then
    throwError $exitcode
  fi
}

addPropVar()
{
  echo -e "\n$1=$2" >> /default.prop
}

setenv()
{
    if [ -z $3 ]; then
       export $1=$2
    else
       export $1=$3
    fi
}

saveEnv()
{
  logd "Saving environment..."
  export > $FSHOOK_PATH_RD/config.sh
}

loadEnv()
{
  # load environment vars (will be the case while re-patching devtree during boot)
  if [ -f $FSHOOK_PATH_RD/config.sh ]; then
      logd "Loading environment..."
      source $FSHOOK_PATH_RD/config.sh
  fi
}

getLogpath()
{
  # check for path of cache-partition
  mount | grep $FSHOOK_PATH_MOUNT_CACHE
  if [ $? -ne 0 ]; then
   logpath=/cache/multiboot
  else
   logpath=$FSHOOK_PATH_MOUNT_CACHE/multiboot
  fi
  
  # create log-folder if it does not exists
  if [ ! -d $logpath ]; then
    mkdir -p $logpath
  fi
}

initlog()
{
  getLogpath
 
  # backup old logfile if there is one
	if [ -f $logpath/multiboot.log ]; then
	   rm -f $logpath/multiboot_last.log
	   mv $logpath/multiboot.log $logpath/multiboot_last.log
	fi
	
	# create new logfile
	echo "" > $logpath/multiboot.log
}

logtofile()
{
  getLogpath
  
  # check if directory exists
	if [ -f $logpath/multiboot.log ]; then
	  # write to logfile
	  echo -e "$1/[`date`]: $2" >> $logpath/multiboot.log
	fi
}

logi()
{
 log -t MULTIBOOT -p i "$1"
 logtofile "I" "$1"
}

loge()
{
 log -t MULTIBOOT -p e "$1"
 logtofile "E" "$1"
}

logw()
{
 log -t MULTIBOOT -p w "$1"
 logtofile "W" "$1"
}

logd()
{
 log -t MULTIBOOT -p d "$1"
 logtofile "D" "$1"
}

logv()
{
 log -t MULTIBOOT -p v "$1"
 logtofile "V" "$1"
}