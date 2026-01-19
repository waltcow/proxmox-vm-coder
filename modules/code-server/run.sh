#!/usr/bin/env bash

EXTENSIONS=("${EXTENSIONS}")
BOLD='\033[0;1m'
CODE='\033[36;40;1m'
RESET='\033[0m'
INSTALL_PREFIX_VALUE="$${INSTALL_PREFIX}"
if [ -z "$${INSTALL_PREFIX_VALUE}" ]; then
  INSTALL_PREFIX_VALUE="/tmp/code-server"
fi
CODE_SERVER="$${INSTALL_PREFIX_VALUE}/bin/code-server"
DOWNLOAD_URL="${DOWNLOAD_URL}"

# Set extension directory
EXTENSION_ARG=""
if [ -n "${EXTENSIONS_DIR}" ]; then
  EXTENSION_ARG="--extensions-dir=${EXTENSIONS_DIR}"
  mkdir -p "${EXTENSIONS_DIR}"
fi

function run_code_server() {
  echo "👷 Running code-server in the background..."
  echo "Check logs at ${LOG_PATH}!"
  $CODE_SERVER "$EXTENSION_ARG" --auth none --port "${PORT}" --app-name "${APP_NAME}" ${ADDITIONAL_ARGS} > "${LOG_PATH}" 2>&1 &
}

function extract_archive() {
  local archive_path="$1"
  local dest_dir="$2"
  if command -v tar > /dev/null 2>&1; then
    tar -xzf "$archive_path" -C "$dest_dir"
    return $?
  fi
  if command -v busybox > /dev/null 2>&1; then
    busybox tar -xzf "$archive_path" -C "$dest_dir"
    return $?
  fi
  printf "tar or busybox is not installed. Please install tar in your image.\n"
  return 1
}

function fetch_archive() {
  local url="$1"
  local dest="$2"
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
    return $?
  fi
  if command -v wget > /dev/null 2>&1; then
    wget -qO "$dest" "$url"
    return $?
  fi
  printf "curl or wget is required to download code-server.\n"
  return 1
}

# Check if the settings file exists...
if [ ! -f ~/.local/share/code-server/User/settings.json ]; then
  echo "⚙️ Creating settings file..."
  mkdir -p ~/.local/share/code-server/User
  if command -v jq &> /dev/null; then
    echo "${SETTINGS}" | jq '.' > ~/.local/share/code-server/User/settings.json
  else
    echo "${SETTINGS}" > ~/.local/share/code-server/User/settings.json
  fi
fi

# Apply/overwrite template based settings
echo "⚙️ Creating machine settings file..."
mkdir -p ~/.local/share/code-server/Machine
if command -v jq &> /dev/null; then
  echo "${MACHINE_SETTINGS}" | jq '.' > ~/.local/share/code-server/Machine/settings.json
else
  echo "${MACHINE_SETTINGS}" > ~/.local/share/code-server/Machine/settings.json
fi

# Check if code-server is already installed for offline
if [ "${OFFLINE}" = true ]; then
  if [ -f "$CODE_SERVER" ]; then
    echo "🥳 Found a copy of code-server"
    run_code_server
    exit 0
  fi
  # Offline mode always expects a copy of code-server to be present
  echo "Failed to find a copy of code-server"
  exit 1
fi

# If there is no cached install OR we don't want to use a cached install
if [ ! -f "$CODE_SERVER" ] || [ "${USE_CACHED}" != true ]; then
  printf "$${BOLD}Installing code-server!\n"

  # Clean up from other install (in case install prefix changed).
  if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ -e "$CODER_SCRIPT_BIN_DIR/code-server" ]; then
    rm "$CODER_SCRIPT_BIN_DIR/code-server"
  fi

  ARGS=(
    "--method=standalone"
    "--prefix=$${INSTALL_PREFIX_VALUE}"
  )
  if [ -n "${VERSION}" ]; then
    ARGS+=("--version=${VERSION}")
  fi

  if [ -n "${DOWNLOAD_URL}" ]; then
    tmp_archive=$(mktemp)
    if ! fetch_archive "${DOWNLOAD_URL}" "$tmp_archive"; then
      echo "Failed to download code-server archive: ${DOWNLOAD_URL}"
      rm -f "$tmp_archive"
      exit 1
    fi
    tmp_dir=$(mktemp -d)
    if ! extract_archive "$tmp_archive" "$tmp_dir"; then
      echo "Failed to extract code-server archive: ${DOWNLOAD_URL}"
      rm -f "$tmp_archive"
      rm -rf "$tmp_dir"
      exit 1
    fi
    extracted_binary=$(find "$tmp_dir" -type f -path "*/bin/code-server" -print -quit)
    if [ -z "$extracted_binary" ]; then
      echo "Failed to locate code-server binary in archive: ${DOWNLOAD_URL}"
      rm -f "$tmp_archive"
      rm -rf "$tmp_dir"
      exit 1
    fi
    extracted_root=$(dirname "$(dirname "$extracted_binary")")
    mkdir -p "$${INSTALL_PREFIX_VALUE}"
    cp -a "$extracted_root"/. "$${INSTALL_PREFIX_VALUE}"/
    rm -f "$tmp_archive"
    rm -rf "$tmp_dir"
    printf "🥳 code-server has been installed in $${INSTALL_PREFIX_VALUE}\n\n"
  else
    output=$(curl -fsSL https://code-server.dev/install.sh | sh -s -- "$${ARGS[@]}")
    if [ $? -ne 0 ]; then
      echo "Failed to install code-server: $output"
      exit 1
    fi
    printf "🥳 code-server has been installed in $${INSTALL_PREFIX_VALUE}\n\n"
  fi
fi

# Make the code-server available in PATH.
if [ -n "$CODER_SCRIPT_BIN_DIR" ] && [ ! -e "$CODER_SCRIPT_BIN_DIR/code-server" ]; then
  ln -s "$CODE_SERVER" "$CODER_SCRIPT_BIN_DIR/code-server"
fi

# Get the list of installed extensions...
LIST_EXTENSIONS=$($CODE_SERVER --list-extensions $EXTENSION_ARG)
readarray -t EXTENSIONS_ARRAY <<< "$LIST_EXTENSIONS"
function extension_installed() {
  if [ "${USE_CACHED_EXTENSIONS}" != true ]; then
    return 1
  fi
  # shellcheck disable=SC2066
  for _extension in "$${EXTENSIONS_ARRAY[@]}"; do
    if [ "$_extension" == "$1" ]; then
      echo "Extension $1 was already installed."
      return 0
    fi
  done
  return 1
}

# Install each extension...
IFS=',' read -r -a EXTENSIONLIST <<< "$${EXTENSIONS}"
# shellcheck disable=SC2066
for extension in "$${EXTENSIONLIST[@]}"; do
  if [ -z "$extension" ]; then
    continue
  fi
  if extension_installed "$extension"; then
    continue
  fi
  printf "🧩 Installing extension $${CODE}$extension$${RESET}...\n"
  output=$($CODE_SERVER "$EXTENSION_ARG" --force --install-extension "$extension")
  if [ $? -ne 0 ]; then
    echo "Failed to install extension: $extension: $output"
    exit 1
  fi
done

if [ "${AUTO_INSTALL_EXTENSIONS}" = true ]; then
  if ! command -v jq > /dev/null; then
    echo "jq is required to install extensions from a workspace file."
    exit 0
  fi

  WORKSPACE_DIR="$HOME"
  if [ -n "${FOLDER}" ]; then
    WORKSPACE_DIR="${FOLDER}"
  fi

  if [ -f "$WORKSPACE_DIR/.vscode/extensions.json" ]; then
    printf "🧩 Installing extensions from %s/.vscode/extensions.json...\n" "$WORKSPACE_DIR"
    # Use sed to remove single-line comments before parsing with jq
    extensions=$(sed 's|//.*||g' "$WORKSPACE_DIR"/.vscode/extensions.json | jq -r '.recommendations[]')
    for extension in $extensions; do
      if extension_installed "$extension"; then
        continue
      fi
      $CODE_SERVER "$EXTENSION_ARG" --force --install-extension "$extension"
    done
  fi
fi

run_code_server
