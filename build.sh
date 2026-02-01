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
# Generate WORKSPACE.bzlmod with mgk repositories
if [ ! -f "WORKSPACE.bzlmod" ]; then
    echo "Creating WORKSPACE.bzlmod with mgk repositories..."
    cat > WORKSPACE.bzlmod << 'EOF'
# Local repository for common kernel sources
local_repository(
    name = "common",
    path = "kernel-6.1",
)

# MGK repository rules for Motorola kernel build
load("//build/bazel_mgk_rules/kleaf:key_value_repo.bzl", "key_value_repo")

key_value_repo(
    name = "mgk_info",
)

key_value_repo(
    name = "mgk_internal",
    additional_values = {
        "mgk_internal": "False",
    },
)

key_value_repo(
    name = "mgk_ko",
    additional_values = {
        "msync2_lic_6.1_set": "False",
        "msync2_lic_6.6_set": "False",
        "msync2_lic_mainline_set": "False",
    },
)
EOF
fi
# Create empty WORKSPACE file (required for Bazel)
if [ ! -L "WORKSPACE" ] && [ ! -f "WORKSPACE" ]; then
    echo "Creating empty WORKSPACE file..."
    touch WORKSPACE
fi

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 DEFCONFIG_OVERLAYS="mt6897_overlay.config cybert_overlay.config" KERNEL_VERSION=kernel-6.1 SOURCE_DATE_EPOCH=0 JAVA_HOME="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86" PATH="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86/bin:${PATH}"

PRIVATE_BAZEL_BUILD_FLAG="--experimental_writable_outputs --config=stamp --repo_manifest=${KERNEL_ROOT_DIR}/${KERNEL_DIR}/fake_manifest.xml"

my_kernel_target=${KERNEL_DEFCONFIG%_defconfig}

PRIVATE_BAZEL_BUILD_GOAL="//${KERNEL_DIR}:mgk_64_k61_modules_install"

PRIVATE_BAZEL_DIST_GOAL="//${KERNEL_DIR}:mgk_64_k61_dist"

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base build ${PRIVATE_BAZEL_BUILD_FLAG} ${PRIVATE_BAZEL_BUILD_GOAL}

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} --nokmi_symbol_list_violations_check ${PRIVATE_BAZEL_DIST_GOAL} -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} //${LINUX_KERNEL_VERSION}:kernel_aarch64_abi_dist -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}/abi
