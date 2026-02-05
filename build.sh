#!/bin/bash
KERNEL_ROOT_DIR=$PWD
TARGET_PRODUCT=cybert
KERNEL_DEFCONFIG="mgk_64_k61_defconfig"
KERNEL_BUILD_VARIANT=user
KERNEL_TARGET_ARCH=arm64
KERNEL_DIR="kernel_device_modules-6.1"
LINUX_KERNEL_VERSION="kernel-6.1"
KERNEL_DEFCONFIG_OVERLAYS="mgk_64_k61_defconfig"
KERNEL_BAZEL_BUILD_OUT=out/target/product/${TARGET_PRODUCT}/obj/KLEAF_OBJ
KERNEL_BAZEL_DIST_OUT=out/target/product/${TARGET_PRODUCT}/obj/KLEAF_OBJ/dist

# Disable Bzlmod as we are missing mgk_ext.bzl
if [ -f "MODULE.bazel" ]; then
    echo "Disabling MODULE.bazel (Bzlmod) as mgk_ext is missing..."
    mv MODULE.bazel MODULE.bazel.disabled
fi
if [ -f "WORKSPACE.bzlmod" ]; then
    rm -f WORKSPACE.bzlmod
fi

# Create WORKSPACE with legacy definitions
if [ ! -L "WORKSPACE" ] && [ ! -f "WORKSPACE" ]; then
    echo "Creating WORKSPACE..."
    cat > WORKSPACE << 'EOF'
load("//build/kernel/kleaf:workspace.bzl", "define_kleaf_workspace")
load("//build/bazel_mgk_rules:kleaf/key_value_repo.bzl", "key_value_repo")

key_value_repo(
    name = "mgk_info",
)

load("@mgk_info//:dict.bzl","KERNEL_VERSION")
define_kleaf_workspace(common_kernel_package = "@//"+KERNEL_VERSION)

load("//build/kernel/kleaf:workspace_epilog.bzl", "define_kleaf_workspace_epilog")
define_kleaf_workspace_epilog()

new_local_repository(
    name="mgk_internal",
    path="vendor/mediatek",
    build_file = "//build/bazel_mgk_rules:kleaf/BUILD.internal"
)

new_local_repository(
    name="mgk_ko",
    path="vendor/mediatek/kernel_modules",
    build_file = "//build/bazel_mgk_rules:kleaf/BUILD.ko"
)
EOF
fi

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 DEFCONFIG_OVERLAYS="../../arch/arm64/configs/ext_config/moto-mgk_64_k61-cybert.config" KERNEL_VERSION=kernel-6.1 SOURCE_DATE_EPOCH=0 JAVA_HOME=java-11-path PATH="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86/bin:${PATH}"

PRIVATE_BAZEL_BUILD_FLAG="--//build/bazel_mgk_rules:kernel_version=${LINUX_KERNEL_VERSION#kernel-} --experimental_writable_outputs --noenable_bzlmod --config=stamp --repo_manifest=${KERNEL_ROOT_DIR}/${KERNEL_DIR}/fake_manifest.xml"

my_kernel_target=${KERNEL_DEFCONFIG%_defconfig}

PRIVATE_BAZEL_BUILD_GOAL="//${KERNEL_DIR#kernel/}:${my_kernel_target}_customer_modules_install.${KERNEL_BUILD_VARIANT}"

PRIVATE_BAZEL_DIST_GOAL="//${KERNEL_DIR#kernel/}:${my_kernel_target}_customer_dist.${KERNEL_BUILD_VARIANT}"

# Run Bazel build
build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base build ${PRIVATE_BAZEL_BUILD_FLAG} ${PRIVATE_BAZEL_BUILD_GOAL}

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} --nokmi_symbol_list_violations_check ${PRIVATE_BAZEL_DIST_GOAL} -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} //${LINUX_KERNEL_VERSION}:kernel_aarch64_abi_dist -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}/abi

# Build DTBs for cybert (mt6897) from device modules sources
echo "Building DTBs for ${TARGET_PRODUCT}..."
mkdir -p ${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}/dtbs

# Set up paths
DTS_DIR="${KERNEL_ROOT_DIR}/${KERNEL_DIR}/arch/${KERNEL_TARGET_ARCH}/boot/dts/mediatek"
CLANG="${KERNEL_ROOT_DIR}/prebuilts/clang/host/linux-x86/clang-r547379/bin/clang"
DTC="${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base/execroot/_main/bazel-out/k8-fastbuild/bin/${KERNEL_DIR}/mgk_64_k61.${KERNEL_BUILD_VARIANT}/scripts/dtc/dtc"

# Include paths for DTS preprocessing
# CRITICAL FIX: Device modules include path must come BEFORE kernel include path
# to pick up the correct header definitions (e.g. mtk-memory-port.h with MTK_M4U_PORT_ID macro)
DTC_INCLUDES="-I${KERNEL_ROOT_DIR}/${KERNEL_DIR}/include \
    -I${KERNEL_ROOT_DIR}/${LINUX_KERNEL_VERSION}/include \
    -I${KERNEL_ROOT_DIR}/${KERNEL_DIR}/arch/${KERNEL_TARGET_ARCH}/boot/dts \
    -I${DTS_DIR}"

# Check if DTC exists (use system dtc as fallback)
if [ ! -f "${DTC}" ]; then
    DTC=$(which dtc 2>/dev/null || echo "")
    if [ -z "${DTC}" ]; then
        echo "Warning: dtc not found, skipping DTB build"
        echo "Build complete! Outputs in: ${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}"
        exit 0
    fi
fi

# Build base DTB: mt6897.dtb
if [ -f "${DTS_DIR}/mt6897.dts" ]; then
    echo "  Building mt6897.dtb..."
    # Using -nostdinc to ensure we use only our explicit include paths in correct order
    ${CLANG} -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp ${DTC_INCLUDES} \
        -o /tmp/mt6897.dts.preprocessed "${DTS_DIR}/mt6897.dts" 2>/dev/null && \
    ${DTC} -@ -I dts -O dtb -o "${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}/dtbs/mt6897.dtb" \
        /tmp/mt6897.dts.preprocessed 2>/dev/null && echo "    -> mt6897.dtb OK" || echo "    -> Failed"
fi

# Build cybert overlay DTBOs
CYBERT_OVERLAYS="mt6897-cybert-dvt-overlay mt6897-cybert-dvt2-overlay mt6897-cybert-evb-overlay \
    mt6897-cybert-pvt-overlay mt6897-cybert-jp-dvt-overlay mt6897-cybert-jp-dvt2-overlay \
    mt6897-cybert-jp-evb-overlay mt6897-cybert-jp-pvt-overlay mt6897-cybert-prc-dvt2-overlay \
    mt6897-cybert-prc-evb-overlay mt6897-cybert-prc-evt3-overlay mt6897-cybert-prc-pvt-overlay"

for overlay in ${CYBERT_OVERLAYS}; do
    if [ -f "${DTS_DIR}/${overlay}.dts" ]; then
        echo "  Building ${overlay}.dtbo..."
        ${CLANG} -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp ${DTC_INCLUDES} \
            -o /tmp/${overlay}.dts.preprocessed "${DTS_DIR}/${overlay}.dts" 2>/dev/null && \
        ${DTC} -@ -I dts -O dtb -o "${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}/dtbs/${overlay}.dtbo" \
            /tmp/${overlay}.dts.preprocessed 2>/dev/null && echo "    -> ${overlay}.dtbo OK" || echo "    -> Failed"
    fi
done

# Clean up temp files
rm -f /tmp/*.dts.preprocessed 2>/dev/null

# List built DTBs
echo ""
echo "DTBs built:"
ls -la ${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}/dtbs/*.dtb* 2>/dev/null || echo "  (none)"

# --- Image Generation ---
echo ""
echo "Generating images..."
DIST_DIR="${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}"
DTB_DIST_DIR="${DIST_DIR}/dtbs"
MKBOOTIMG="${KERNEL_ROOT_DIR}/prebuilts/kernel-build-tools/linux_musl-x86/bin/mkbootimg"
MKDTBOIMG="${KERNEL_ROOT_DIR}/prebuilts/kernel-build-tools/linux_musl-x86/bin/mkdtboimg"
# Find kernel image - use LZ4 compressed kernel (verified stock uses LZ4)
KERNEL_IMAGE=$(find ${DIST_DIR} -name "Image.lz4" -type f | grep -v "bazel-out" | head -1)

# Partition size from BoardConfig.mk
BOARD_BOOTIMAGE_PARTITION_SIZE=67108864

# 1. Generate boot.img (Kernel only, matching LineageOS structure)
# BOARD_MKBOOTIMG_ARGS from LineageOS BoardConfig.mk:
#   --dtb_offset, --header_version, --kernel_offset, --ramdisk_offset, --tags_offset
if [ -n "${KERNEL_IMAGE}" ] && [ -f "${MKBOOTIMG}" ]; then
    echo "  Creating boot.img..."
    ${MKBOOTIMG} \
        --header_version 4 \
        --kernel "${KERNEL_IMAGE}" \
        --kernel_offset 0x00000000 \
        --ramdisk_offset 0x26f00000 \
        --tags_offset 0x07c80000 \
        --dtb_offset 0x07c80000 \
        --os_version 16.0.0 \
        --os_patch_level 2025-12 \
        --output "${DIST_DIR}/boot.img"
    # Pad to partition size (matches LineageOS build)
    truncate -s ${BOARD_BOOTIMAGE_PARTITION_SIZE} "${DIST_DIR}/boot.img"
    echo "    -> boot.img created and padded to ${BOARD_BOOTIMAGE_PARTITION_SIZE} bytes"
else
    echo "  Skipping boot.img: Kernel Image or mkbootimg not found"
    [ -z "${KERNEL_IMAGE}" ] && echo "    Missing: Kernel Image in dist"
    [ ! -f "${MKBOOTIMG}" ] && echo "    Missing: ${MKBOOTIMG}"
fi

# 2. Generate dtbo.img (Overlays)
# BOARD_DTBOIMG_PARTITION_SIZE from BoardConfig.mk
BOARD_DTBOIMG_PARTITION_SIZE=8388608

if [ -f "${MKDTBOIMG}" ]; then
    echo "  Creating dtbo.img..."
    # Use alphabetical ordering for consistency
    # Bootloader matches overlays based on hardware detection, not index order
    DTBO_FILES=$(find ${DTB_DIST_DIR} -name "*.dtbo" -type f | sort)
    
    if [ -n "${DTBO_FILES}" ]; then
        DTBO_ARGS=""
        DTBO_ID=0
        for dtbo in ${DTBO_FILES}; do
            DTBO_ARGS="${DTBO_ARGS} ${dtbo} --id=${DTBO_ID}"
            DTBO_ID=$((DTBO_ID + 1))
        done
        ${MKDTBOIMG} create "${DIST_DIR}/dtbo.img" ${DTBO_ARGS}
        # Pad to partition size (matches stock)
        truncate -s ${BOARD_DTBOIMG_PARTITION_SIZE} "${DIST_DIR}/dtbo.img"
        echo "    -> dtbo.img created with ${DTBO_ID} overlays, padded to ${BOARD_DTBOIMG_PARTITION_SIZE} bytes"
    else
        echo "    No .dtbo files found for dtbo.img"
    fi
else
    echo "  Skipping dtbo.img: mkdtboimg not found"
fi

# 3. Generate dtb.img (Base DTB + Overlays concatenated, commonly used on MediaTek)
# Note: Some devices strictly need the base DTB first, then overlays.
echo "  Creating dtb.img..."
if [ -f "${DTB_DIST_DIR}/mt6897.dtb" ]; then
    cat "${DTB_DIST_DIR}/mt6897.dtb" > "${DIST_DIR}/dtb.img"
    # Append overlays if they exist
    find ${DTB_DIST_DIR} -name "*.dtbo" | sort | xargs cat >> "${DIST_DIR}/dtb.img" 2>/dev/null
    echo "    -> dtb.img created at ${DIST_DIR}/dtb.img"
else
    echo "    Skipping dtb.img: Base DTB mt6897.dtb not found"
fi

# --- Module Organization ---
echo ""
echo "Organizing modules..."
# Search in the entire device modules output directory to find both GKI and Vendor modules
# GKI modules are often in mgk_64_k61* dirs, Vendor in *_modules_install.
MODULES_SEARCH_PATH="${DIST_DIR}/kernel_device_modules-6.1"

if [ -d "${MODULES_SEARCH_PATH}" ]; then
    echo "  Searching for modules in: ${MODULES_SEARCH_PATH}"
    
    # Define destination directories
    SYSTEM_MOD_DIR="${DIST_DIR}/system"
    VENDOR_MOD_DIR="${DIST_DIR}/vendor"
    VENDOR_RAMDISK_MOD_DIR="${DIST_DIR}/vendor_ramdisk"
    
    mkdir -p "${SYSTEM_MOD_DIR}" "${VENDOR_MOD_DIR}" "${VENDOR_RAMDISK_MOD_DIR}"
    
    # Helper function to copy modules from list
    copy_modules() {
        local list_file="$1"
        local dest_dir="$2"
        local label="$3"
        
        if [ -f "${list_file}" ]; then
            echo "  Processing ${label} from $(basename ${list_file})..."
            while IFS= read -r module || [ -n "$module" ]; do
                # Trim whitespace
                module=$(echo "$module" | xargs)
                [ -z "$module" ] && continue
                [ "${module:0:1}" = "#" ] && continue # Skip comments
                
                # Find module file (handle potential paths or just filename)
                local mod_name=$(basename "$module")
                # Find the module recursively in the search path
                # Use head -1 to pick the first match if duplicates exist (usually identical)
                local src_path=$(find "${MODULES_SEARCH_PATH}" -name "${mod_name}" 2>/dev/null | head -1)
                
                if [ -n "${src_path}" ]; then
                    cp -f "${src_path}" "${dest_dir}/"
                else
                    echo "    Warning: Module ${mod_name} not found in build output"
                fi
            done < "${list_file}"
            echo "    -> Copied to ${dest_dir}"
        else
            echo "  Skipping ${label}: List file not found: ${list_file}"
        fi
    }

    # 1. System Modules
    copy_modules "${KERNEL_ROOT_DIR}/build/manifest/modules.load.system" "${SYSTEM_MOD_DIR}" "System Modules"
    
    # 2. Vendor Modules
    # Check for modules.load.vendor OR modules.recovery.vendor as user hinted variability
    if [ -f "${KERNEL_ROOT_DIR}/build/manifest/modules.load.vendor" ]; then
        copy_modules "${KERNEL_ROOT_DIR}/build/manifest/modules.load.vendor" "${VENDOR_MOD_DIR}" "Vendor Modules"
    elif [ -f "${KERNEL_ROOT_DIR}/build/manifest/modules.recovery.vendor" ]; then
        copy_modules "${KERNEL_ROOT_DIR}/build/manifest/modules.recovery.vendor" "${VENDOR_MOD_DIR}" "Vendor Modules"
    fi

    # 3. Vendor Ramdisk Modules
    if [ -f "${KERNEL_ROOT_DIR}/build/manifest/modules.load.vendor_ramdisk" ]; then
        copy_modules "${KERNEL_ROOT_DIR}/build/manifest/modules.load.vendor_ramdisk" "${VENDOR_RAMDISK_MOD_DIR}" "Vendor Ramdisk Modules"
    fi
    # Recovery modules generally go to vendor_ramdisk in generic setups, or separate recovery ramdisk.
    # User requested: "recovery goes in vendor_ramdisk"
    if [ -f "${KERNEL_ROOT_DIR}/build/manifest/modules.load.recovery" ]; then
        copy_modules "${KERNEL_ROOT_DIR}/build/manifest/modules.load.recovery" "${VENDOR_RAMDISK_MOD_DIR}" "Recovery Modules (to vendor_ramdisk)"
    fi

else
    echo "Warning: Could not find modules installation directory in dist"
fi

echo ""
echo "Build complete! Outputs in: ${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}"