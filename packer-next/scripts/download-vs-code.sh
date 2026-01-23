#!/bin/sh

# Copyright 2026 Khalifah K. Shabazz
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

set -e

usage="
This script downloads VS Code Server/CLI/Web and extracts it to the appropriate location.

download-vs-code.sh [options] <PLATFORM> <ARCH>

Example:
  download-vs-code.sh linux x64
  download-vs-code.sh --cli linux x64
  download-vs-code.sh --web linux x64

Options

--insider
    Switches to the pre-released version.

--dump-sha
    Will print the latest commit sha for VS Code.

--cli
    Download VS Code CLI instead of Server.

--web
    Download VS Code Web.

--use-commit
    Download with the provided commit sha.

-h, --help
    Print this usage info.
"

# Get the latest VS Code commit sha.
get_latest_release() {
    platform=${1}
    arch=${2}
    bin_type="${3}"

    commit_id=$(curl --silent "https://update.code.visualstudio.com/api/commits/${bin_type}/${platform}-${arch}" | sed s'/^\["\([^"]*\).*$/\1/')
    printf "%s" "${commit_id}"
}

install_cli() {
    echo "setup directories:"
    mkdir -vp ~/.vscode-server
    echo "done"

    # Extract the tarball to the right location.
    printf "%s" "extracting ${archive}..."
    tar -xz -C ~/.vscode-server --no-same-owner -f "/tmp/${archive}"
    echo "done"

    # Add symlinks
    printf "%s" "setup symlinks..."
    ln -sf ~/.vscode-server/code ~/.vscode-server/code-"${commit_sha}"
    ln -sf "${HOME}"/.vscode-server/code ~/code
    echo "done"
}

install_server() {
    echo "setup directories:"
    mkdir -vp ~/.vscode-server/bin/"${commit_sha}"
    mkdir -vp ~/.vscode-server/extensions
    mkdir -vp ~/.vscode-server/extensionsCache
    mkdir -vp ~/.vscode/cli/servers/Stable-"${commit_sha}"
    mkdir -vp ~/.vscode-server/cli/servers/Stable-"${commit_sha}"
    echo "done"

    # Extract the tarball to the right location.
    printf "%s" "extracting ${archive}..."
    tar -xz -C ~/.vscode-server/bin/"${commit_sha}" --strip-components=1 --no-same-owner -f "/tmp/${archive}"
    echo "done"

    # Add symlinks
    printf "%s" "setup symlinks..."
    ln -sf ~/.vscode-server/bin/"${commit_sha}" ~/.vscode-server/bin/default_version
    ln -sf ~/.vscode-server/bin/"${commit_sha}" ~/.vscode/cli/servers/Stable-"${commit_sha}"/server
    ln -sf ~/.vscode-server/bin/"${commit_sha}" ~/.vscode-server/cli/servers/Stable-"${commit_sha}"/server
    ln -sf ~/.vscode-server/bin/"${commit_sha}"/bin/code-server ~/code-server
    echo "done"
}

install_web() {
    echo "setup directories:"
    mkdir -vp ~/.vscode-web
    echo "done"

    # Extract the tarball to the right location.
    printf "%s" "extracting ${archive}..."
    tar -xz -C ~/.vscode-web --strip-components=1 --no-same-owner -f "/tmp/${archive}"

    # Make binaries executable
    chmod +x ~/.vscode-web/bin/code-server
    chmod +x ~/.vscode-web/node

    # Write commit id
    echo "${commit_sha}" > ~/.vscode-web/.commit_id

    echo "done"
}

## Parse command line options
getopt --test > /dev/null && true
if [ $? -ne 4 ]; then
    echo 'sorry, getopts --test` failed in this environment'
    exit 1
fi

LONG_OPTS=help,insider,dump-sha,cli,web,use-commit:
OPTIONS=h

PARSED=$(getopt --options=${OPTIONS} --longoptions=${LONG_OPTS} --name "$0" -- "${@}") || exit 1
eval set -- "${PARSED}"

PLATFORM=""
ARCH=""
BUILD="stable"
BIN_TYPE="server"
DUMP_COMMIT_SHA=""
IS_WEB=0
USE_COMMIT=""

while [ true ]; do
    case ${1} in
        --insider)
            BUILD="insider"
            shift
            ;;
        --dump-sha)
            DUMP_COMMIT_SHA="yes"
            shift
            ;;
        --cli)
            BIN_TYPE="cli"
            shift
            ;;
        --web)
            IS_WEB=1
            shift
            ;;
        --use-commit)
            USE_COMMIT="${2}"
            shift 2
            ;;
        -h|--help)
            echo "${usage}"
            exit 0
            ;;
        --) shift; break;;
        *) echo "unknown option '${1}'"; exit 1;;
    esac
done

# Platform is required.
if [ "$#" -lt 1 ]; then
    echo "please specify which platform version of VS Code to install (linux, darwin, win32)"
    exit 1
fi

if [ "$#" -lt 2 ]; then
    echo "missing required architecture argument <ARCH> (arm64|armhf|x64)"
    exit 1
fi

case ${1} in
    darwin|linux|win32)
      PLATFORM="${1}"
      ;;
    *)
      echo "invalid platform: ${1}"
      exit 1
      ;;
esac

case ${2} in
    arm64|armhf|x64)
      ARCH="${2}"
      ;;
    *)
      # Auto-detect from OS
      U_NAME=$(uname -m)
      if [ "${U_NAME}" = "aarch64" ]; then
          ARCH="arm64"
      elif [ "${U_NAME}" = "x86_64" ]; then
          ARCH="x64"
      elif [ "${U_NAME}" = "armv7l" ]; then
          ARCH="armhf"
      else
          echo "could not detect architecture"
          exit 1
      fi
      ;;
esac

if [ -n "${USE_COMMIT}" ]; then
    commit_sha="${USE_COMMIT}"
else
    commit_sha=$(get_latest_release "win32" "x64" "${BUILD}")
fi

if [ -z "${commit_sha}" ]; then
    echo "could not get the VS Code latest commit sha, exiting"
    exit 1
fi

if [ "${DUMP_COMMIT_SHA}" = "yes" ]; then
    echo "${commit_sha}"
    exit 0
fi

if [ ${IS_WEB} -eq 1 ]; then
    echo "attempting to download and pre-install VS Code Web version '${commit_sha}'"
    options="server-${PLATFORM}-${ARCH}-web"
else
    echo "attempting to download and pre-install VS Code ${BIN_TYPE} version '${commit_sha}'"
    options="${BIN_TYPE}-${PLATFORM}-${ARCH}"
fi

archive="vscode-${options}.tar.gz"

# Download VS Code tarball
url="https://update.code.visualstudio.com/commit:${commit_sha}/${options}/${BUILD}"
printf "%s" "downloading ${url} to ${archive} "
curl -s --fail -L "${url}" -o "/tmp/${archive}"
echo "done"

# Based on the binary type chosen, perform the installation.
if [ ${IS_WEB} -eq 1 ]; then
    install_web
elif [ "${BIN_TYPE}" = "cli" ]; then
    install_cli
else
    install_server
fi

echo "VS Code pre-install completed"
