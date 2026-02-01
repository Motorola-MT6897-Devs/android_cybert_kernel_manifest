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
    echo "Creating MODULE.bazel symlink..."
    ln -s build/kernel/kleaf/bzlmod/bazel.MODULE.bazel MODULE.bazel
fi
if [ ! -f "WORKSPACE.bzlmod" ]; then
    echo "Creating WORKSPACE.bzlmod symlink..."
    ln -s build/kernel/kleaf/bzlmod/bazel.WORKSPACE.bzlmod WORKSPACE.bzlmod
fi
if [ ! -L "WORKSPACE" ] && [ ! -f "WORKSPACE" ]; then
    echo "Creating WORKSPACE file with required repositories..."
    cat > WORKSPACE << 'EOF'
local_repository(
    name = "common",
    path = "kernel-6.1",
)

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

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1 DEFCONFIG_OVERLAYS="mt6897_overlay.config cybert_overlay.config" KERNEL_VERSION=kernel-6.1 SOURCE_DATE_EPOCH=0 JAVA_HOME="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86" PATH="${KERNEL_ROOT_DIR}/prebuilts/jdk/jdk11/linux-x86/bin:${PATH}"

PRIVATE_BAZEL_BUILD_FLAG="--experimental_writable_outputs --config=stamp --repo_manifest=${KERNEL_ROOT_DIR}/${KERNEL_DIR}/fake_manifest.xml"

my_kernel_target=${KERNEL_DEFCONFIG%_defconfig}

PRIVATE_BAZEL_BUILD_GOAL="//${KERNEL_DIR}:mgk_64_k61_modules_install"

PRIVATE_BAZEL_DIST_GOAL="//${KERNEL_DIR}:mgk_64_k61_dist"

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base build ${PRIVATE_BAZEL_BUILD_FLAG} ${PRIVATE_BAZEL_BUILD_GOAL}

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} --nokmi_symbol_list_violations_check ${PRIVATE_BAZEL_DIST_GOAL} -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}

build/kernel/kleaf/bazel.sh --output_root=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT} --output_base=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_BUILD_OUT}/bazel/output_user_root/output_base run ${PRIVATE_BAZEL_BUILD_FLAG} //${LINUX_KERNEL_VERSION}:kernel_aarch64_abi_dist -- --dist_dir=${KERNEL_ROOT_DIR}/${KERNEL_BAZEL_DIST_OUT}/abi
