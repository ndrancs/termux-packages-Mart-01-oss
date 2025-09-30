rm -fr ~/.termux-build/vulkan1
export NDK=/data/data/com.termux/files/home/android-ndk-r27b
export TERMUX_PKG_API_LEVEL=26
bash -c "NDK=~/android-ndk-r27b ./build-package.sh --library bionic vulkan1 -s -F"
cp /data/data/com.termux/files/usr/lib/libvulkan_wrapper.so /sdcard
cp /data/data/com.termux/files/usr/lib/libadrenotools.so /sdcard
rm -fr ~/.termux-build/vulkan1
