 #!/bin/bash

#need to:
# pip install enum34
# pip install pyelftools

# Example entries:
# Mcsema installed to a virtualenv in /store/artem/diversity
#MCSEMA_DIR=/store/artem/diversity
# McSema source in the remill directory at /store/artem/diversity/remill/tools/mcsema
#MCSEMA_SRC=/store/artem/diversity/remill/tools/mcsema
# For now, We must use the LLVM 3.8 toolchain as thats what the multicompiler ships
LLVM_VERSION=3.8
# Location of the multicompiler
#MCOMP_DIR=/store/artem/diversity/multicompiler/install/bin/

# Set values for your installation here
MCSEMA_DIR= /usr/local/
MCSEMA_SRC= /usr/local/src/
MCOMP_DIR= /usr/local/bin/

CXX=clang++-${LLVM_VERSION}
LIFTER=${MCSEMA_DIR}/bin/mcsema-lift-${LLVM_VERSION}
ABI_DIR=${MCSEMA_DIR}/share/mcsema/${LLVM_VERSION}/ABI/linux/

IN_DIR=$(pwd)
IN_FILE=${1}
OUT_DIR=$(pwd)
# This should be your IDA installation directory.
#IDA_DIR=/home/artem/ida-6.9
IDA_DIR=/root/binaryninja

function sanity_check
{

  if [[ -z "${MCSEMA_DIR}" ]]
  then
    echo "Please edit this script and set MCSEMA_DIR to the mcsema *installation* directory"
    exit 1
  fi

  local abi_lib="${ABI_DIR}/ABI_exceptions_amd64.bc"
  if [[ ! -f "${abi_lib}" ]]
  then
    echo "ABI library for exceptions not found (checked: [${abi_lib}])."
    echo "Please rebuild mcsema via: "
    echo ""
    echo "    cd ${MCSEMA_SRC}/../../remill-build"
    echo "    cmake -DMCSEMA_DISABLED_ABI_LIBRARIES:STRING=\"\" .."
    echo "    make -j`nproc` install"
    exit 1
  fi

  if [[ -z "${MCSEMA_SRC}" ]]
  then
    echo "Please edit this script and set MCSEMA_DIR to the mcsema *source code* directory"
    exit 1
  fi

  if [[ -z "${IDA_DIR}" ]]
  then
    echo "Please edit this script and set the IDA_DIR variable to where IDA Pro is installed"
    exit 1
  fi

  if [[ -z "${LLVM_VERSION}" ]]
  then
    echo "Please edit this script and set LLVM_VERSION to the desired LLVM version (e.g. 4.0)"
    exit 1
  fi

  if [[ ! -f "${LIFTER}" ]]
  then
    echo "Could not find McSema installation. Looked for [${LIFTER}]"
    exit 1
  fi

  if [[ "${1}" == "diversify" ]]
  then
    local mcomp_bin="${MCOMP_DIR}/clang++"
    if [[ ! -f "${mcomp_bin}" ]]
    then
      echo "Could not find multicompiler. Looked for it in [${mcomp_bin}]"
      echo "Please set MCOMP_DIR in this script to the multicompiler's installation directory"
      exit 1
    fi

    ${MCOMP_DIR}/clang++ --version | grep -q "clang version ${LLVM_VERSION}"
    if [ $? -ne 0 ]
    then
      echo "Version mismatch between Multicompiler and McSema"
      echo "    Multicompiler: `${MCOMP_DIR}/clang++ --version | grep -o 'clang version ...'`"
      echo "    McSema: ${LLVM_VERSION}"
      exit 1
    fi
  fi

}

function clean_and_build
{
  echo "Cleaning old output..."
  local in_file=${1}
  rm -rf ${OUT_DIR}/${in_file}.cfg ${OUT_DIR}/${in_file}.bc ${OUT_DIR}/${in_file}_out.txt ${OUT_DIR}/${in_file}_lifted* dwarf_debug.log global.protobuf
  echo "Building new 'example' binary"
  ${CXX} -m64 -g -Wall -O0 -o example example.cpp
}

function recover_globals
{
  echo "Recovering Globals..."
  local in_file=${1}
  ${MCSEMA_SRC}/tools/mcsema_disass/ida/var_recovery.py --binary \
    ${IN_DIR}/${in_file} \
    --out ${OUT_DIR}/global.protobuf \
    --log_file dwarf_debug.log
}

function recover_cfg
{
  echo "Recovering CFG and Stack Variables..."
  local in_file=${1}
  mcsema-disass --disassembler ${IDA_DIR}/binaryninja \
    --entrypoint main \
    --arch amd64 \
    --os linux \
    --binary ${IN_DIR}/${in_file} \
    --output ${OUT_DIR}/${in_file}.cfg \
    --log_file ${OUT_DIR}/${in_file}_out.txt
}

function lift_binary
{
  echo "Lifting binary..."
  local in_file=${1}
  mcsema-lift-3.8 --arch amd64 \
    --os linux \
    --cfg ${OUT_DIR}/${in_file}.cfg \
    --output ${OUT_DIR}/${in_file}.bc
}

function new_binary
{
  echo "Generating lifted binary..."
  local in_file=${1}
  remill-clang-3.8 -rdynamic -O3 -o ${in_file}-lifted ${in_file}.bc /usr/local/lib/libmcsema_rt64-3.8.a -llzma
}

function diversify_binary
{
 # if [[ -z "${MCOMP_DIR}" ]]
 # then
 #   echo "Please edit this script and set MCOMP_DIR to the location of the multicompiler"
 #   exit 1
 # fi

  local MCOMP="clang++"
  local in_file=${1}
  local RANDOM_SEED=42
  local MCOMP_CFLAGS="-flto -fuse-ld=gold -frandom-seed=${RANDOM_SEED}"
  local MCOMP_LDFLAGS="-Wl,--plugin-opt,-random-seed=${RANDOM_SEED} \
    -Wl,--plugin-opt,-randomize-function-list"

  echo ${MCOMP} -m64 ${MCOMP_CFLAGS} \
    ${MCOMP_LDFLAGS} \
    -rdynamic -o ${OUT_DIR}/${in_file}-diverse \
    ${OUT_DIR}/${in_file}.bc \
    /usr/local/lib/libmcsema_rt64-3.8.a -llzma

  ${MCOMP} -m64 ${MCOMP_CFLAGS} \
    ${MCOMP_LDFLAGS} \
    -rdynamic -o ${OUT_DIR}/${in_file}-diverse \
    ${OUT_DIR}/${in_file}.bc \
    /usr/local/lib/libmcsema_rt64-3.8.a -llzma

}

rm ${OUT_DIR}/${IN_FILE}.cfg ${OUT_DIR}/${IN_FILE}.bc ${OUT_DIR}/${IN_FILE}_out.txt ${OUT_DIR}/${IN_FILE}-lifted  ${OUT_DIR}/${IN_FILE}-diverse
# sanity_check "${1}"

# clean_and_build ${IN_FILE}

# recover_globals ${IN_FILE}
if [ "${2}" == "clean" ]
then
exit 0
fi

recover_cfg ${IN_FILE}

lift_binary ${IN_FILE}

new_binary ${IN_FILE}

if [[ "${2}" == "diversify" ]]
then
  diversify_binary ${IN_FILE}
fi

