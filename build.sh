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

# Link Bazel files
if [ ! -L "common" ] && [ ! -d "common" ]; then
    echo "Creating common symlink to kernel-6.1..."
    ln -s kernel-6.1 common
fi
if [ ! -f "MODULE.bazel" ]; then
    echo "Creating MODULE.bazel with mgk extension..."
    cat build/kernel/kleaf/bzlmod/bazel.MODULE.bazel > MODULE.bazel
    cat >> MODULE.bazel << 'EOF'

# MGK extension for Motorola kernel builds
mgk_ext = use_extension("//build/bazel_mgk_rules:mgk_ext.bzl", "mgk_ext")
use_repo(mgk_ext, "mgk_info")
use_repo(mgk_ext, "mgk_internal")
use_repo(mgk_ext, "mgk_ko")
EOF
fi
if [ ! -f "WORKSPACE.bzlmod" ]; then
    touch WORKSPACE.bzlmod
fi
if [ ! -L "WORKSPACE" ] && [ ! -f "WORKSPACE" ]; then
    touch WORKSPACE
fi

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 DEFCONFIG_OVERLAYS="" KERNEL_VERSION=kernel-6.1 SOURCE_DATE_EPOCH=0 JAVA_HOME="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86" PATH="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86/bin:${PATH}"

PRIVATE_BAZEL_BUILD_FLAG="--experimental_writable_outputs --config=stamp --noincompatible_disallow_empty_glob --repo_manifest=${KERNEL_ROOT_DIR}/${KERNEL_DIR}/fake_manifest.xml"

PRIVATE_BAZEL_DIST_GOAL="//${KERNEL_DIR}:mgk_64_k61_customer_dist.${KERNEL_BUILD_VARIANT}"

# Run Bazel build
build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} --nokmi_symbol_list_violations_check ${PRIVATE_BAZEL_DIST_GOAL} -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}

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

echo ""
echo "Build complete! Outputs in: ${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}"
