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
# Create common symlink to kernel-6.1 (required by kleaf toolchain)
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
# Generate WORKSPACE.bzlmod (unused in bzlmod but may be needed for compatibility)
if [ ! -f "WORKSPACE.bzlmod" ]; then
    echo "Creating empty WORKSPACE.bzlmod..."
    touch WORKSPACE.bzlmod
fi
# Create empty WORKSPACE file (required for Bazel)
if [ ! -L "WORKSPACE" ] && [ ! -f "WORKSPACE" ]; then
    echo "Creating empty WORKSPACE file..."
    touch WORKSPACE
fi

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 DEFCONFIG_OVERLAYS="" KERNEL_VERSION=kernel-6.1 SOURCE_DATE_EPOCH=0 JAVA_HOME="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86" PATH="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86/bin:${PATH}"

PRIVATE_BAZEL_BUILD_FLAG="--experimental_writable_outputs --config=stamp --repo_manifest=${KERNEL_ROOT_DIR}/${KERNEL_DIR}/fake_manifest.xml"

my_kernel_target=${KERNEL_DEFCONFIG%_defconfig}

PRIVATE_BAZEL_BUILD_GOAL="//${KERNEL_DIR}:mgk_64_k61_customer_modules_install.${KERNEL_BUILD_VARIANT}"

PRIVATE_BAZEL_DIST_GOAL="//${KERNEL_DIR}:mgk_64_k61_customer_dist.${KERNEL_BUILD_VARIANT}"

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base build ${PRIVATE_BAZEL_BUILD_FLAG} ${PRIVATE_BAZEL_BUILD_GOAL}

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} --nokmi_symbol_list_violations_check ${PRIVATE_BAZEL_DIST_GOAL} -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}

# NOTE: Commented out until kernel-6.1/BUILD.bazel is updated for newer kleaf API
# build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} //${LINUX_KERNEL_VERSION}:kernel_aarch64_abi_dist -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}/abi
