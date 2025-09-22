#!/bin/bash

# Define colors and text styles
BOLD=$(tput bold)
RESET=$(tput sgr0)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)

# Define the log file location
LOG_FILE="/tmp/update_log.txt"

# Initialize the log file
echo "Starting update at $(date)..." > "$LOG_FILE"

# Helper functions for displaying progress
function display_message() {
  echo -n "${BOLD}$1${RESET}...  "
}

function complete_message() {
  echo -e "${GREEN}Done.${RESET}"
}

function skip_message() {
  echo -e "${YELLOW}Skipped.${RESET}"
}

function info_message() {
  echo -e "${BLUE}$1${RESET}"
}

# Function for showing a spinner while a command runs
function spinner() {
  local pid=$!
  local delay=0.1
  local spin=('-' '\' '|' '/')
  while kill -0 "$pid" 2>/dev/null; do
    for i in "${spin[@]}"; do
      echo -ne "\b$i" > /dev/tty
      sleep $delay
    done
  done
  wait $pid
  local exit_code=$?
  echo -ne "\b"
  return $exit_code
}

# Run a command with spinner
function run_with_spinner() {
  display_message "$1"
  eval "$2" >> "$LOG_FILE" 2>&1 & spinner
  if [ $? -eq 0 ]; then
    complete_message
    return 0
  else
    echo -e "${BOLD}${YELLOW}Failed.${RESET} Check log for details."
    return 1
  fi
}

# Define a custom apt function to enforce DEBIAN_FRONTEND
function apt2() {
  sudo DEBIAN_FRONTEND=noninteractive apt "$@"
}

# Function to check if a command exists
function command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to get current version of a tool
function get_current_version() {
  case "$1" in
    "quarto")
      if command_exists quarto; then
        quarto --version 2>/dev/null || echo "unknown"
      else
        echo "not installed"
      fi
      ;;
    "rstudio-server")
      if command_exists rstudio-server; then
        rstudio-server version 2>/dev/null | cut -d' ' -f1 || echo "unknown"
      else
        echo "not installed"
      fi
      ;;
    "duckdb")
      if command_exists duckdb; then
        duckdb --version 2>/dev/null | grep -oP 'v\K[\d.]+' || echo "unknown"
      else
        echo "not installed"
      fi
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Parse command line arguments
UPDATE_ALL=true
UPDATE_SYSTEM=false
UPDATE_R=false
UPDATE_QUARTO=false
UPDATE_RSTUDIO=false
UPDATE_VSCODE=false
UPDATE_DUCKDB=false
UPDATE_TOOLS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --system)
      UPDATE_ALL=false
      UPDATE_SYSTEM=true
      shift
      ;;
    --r)
      UPDATE_ALL=false
      UPDATE_R=true
      shift
      ;;
    --quarto)
      UPDATE_ALL=false
      UPDATE_QUARTO=true
      shift
      ;;
    --rstudio)
      UPDATE_ALL=false
      UPDATE_RSTUDIO=true
      shift
      ;;
    --vscode)
      UPDATE_ALL=false
      UPDATE_VSCODE=true
      shift
      ;;
    --duckdb)
      UPDATE_ALL=false
      UPDATE_DUCKDB=true
      shift
      ;;
    --tools)
      UPDATE_ALL=false
      UPDATE_TOOLS=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --system    Update system packages only"
      echo "  --r         Update R only"
      echo "  --quarto    Update Quarto only"
      echo "  --rstudio   Update RStudio Server only"
      echo "  --vscode    Update VS Code and extensions only"
      echo "  --duckdb    Update DuckDB only"
      echo "  --tools     Update development tools (Rust, uv, ruff, sqlfluff, rig) only"
      echo "  --help, -h  Show this help message"
      echo ""
      echo "If no options are specified, all components will be updated."
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Define software versions (can be overridden by environment variables)
QUARTO_VERSION=${QUARTO_VERSION:-"1.8.24"}
RSTUDIO_SERVER_VERSION=${RSTUDIO_SERVER_VERSION:-"2025.09.0-387"}
DUCKDB_VERSION=${DUCKDB_VERSION:-"1.4.0"}

echo -e "\n${BOLD}GCP Instance Update Script${RESET}"
echo "================================"
echo "Log file: ${GREEN}${LOG_FILE}${RESET}"
echo ""

# Display what will be updated
if [ "$UPDATE_ALL" = true ]; then
  info_message "Updating all components..."
else
  info_message "Selective update mode:"
  [ "$UPDATE_SYSTEM" = true ] && echo "  - System packages"
  [ "$UPDATE_R" = true ] && echo "  - R"
  [ "$UPDATE_QUARTO" = true ] && echo "  - Quarto"
  [ "$UPDATE_RSTUDIO" = true ] && echo "  - RStudio Server"
  [ "$UPDATE_VSCODE" = true ] && echo "  - VS Code and extensions"
  [ "$UPDATE_DUCKDB" = true ] && echo "  - DuckDB"
  [ "$UPDATE_TOOLS" = true ] && echo "  - Development tools"
fi
echo ""

# 1. Update system packages
if [ "$UPDATE_ALL" = true ] || [ "$UPDATE_SYSTEM" = true ]; then
  run_with_spinner "Updating system packages" \
    "apt2 update && apt2 upgrade -y"
fi

# 2. Update R
if [ "$UPDATE_ALL" = true ] || [ "$UPDATE_R" = true ]; then
  if command_exists R; then
    run_with_spinner "Updating R" \
      "apt2 update && apt2 install -y r-base r-base-dev"
  else
    info_message "R is not installed. Skipping R update."
  fi
fi

# 3. Update Quarto
if [ "$UPDATE_ALL" = true ] || [ "$UPDATE_QUARTO" = true ]; then
  if command_exists quarto; then
    current_version=$(get_current_version "quarto")
    info_message "Current Quarto version: $current_version"
    info_message "Target Quarto version: $QUARTO_VERSION"

    if [ "$current_version" != "$QUARTO_VERSION" ]; then
      run_with_spinner "Updating Quarto to version $QUARTO_VERSION" "
        wget -q https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz && \
        tar -xzf quarto-${QUARTO_VERSION}-linux-amd64.tar.gz && \
        sudo rm -rf /opt/quarto-* && \
        sudo mv quarto-${QUARTO_VERSION} /opt/quarto-${QUARTO_VERSION} && \
        sudo rm -f /usr/local/bin/quarto && \
        sudo ln -s /opt/quarto-${QUARTO_VERSION}/bin/quarto /usr/local/bin/quarto && \
        rm quarto-${QUARTO_VERSION}-linux-amd64.tar.gz
      "

      # Update TinyTeX if it's installed
      if [ -d "$HOME/.TinyTeX" ] || [ -d "/opt/TinyTeX" ]; then
        run_with_spinner "Updating TinyTeX" \
          "/opt/quarto-${QUARTO_VERSION}/bin/quarto install tinytex --update-path --no-prompt"
      fi
    else
      info_message "Quarto is already at version $current_version. Skipping update."
    fi
  else
    info_message "Quarto is not installed. Skipping Quarto update."
  fi
fi

# 4. Update RStudio Server
if [ "$UPDATE_ALL" = true ] || [ "$UPDATE_RSTUDIO" = true ]; then
  if command_exists rstudio-server; then
    current_version=$(get_current_version "rstudio-server")
    info_message "Current RStudio Server version: $current_version"
    info_message "Target RStudio Server version: $RSTUDIO_SERVER_VERSION"

    # Stop RStudio Server before updating
    run_with_spinner "Stopping RStudio Server" \
      "sudo systemctl stop rstudio-server"

    run_with_spinner "Updating RStudio Server to version $RSTUDIO_SERVER_VERSION" \
      "wget -q https://download2.rstudio.org/server/jammy/amd64/rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb && \
        sudo gdebi -n rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb && \
        rm rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb"

    # Start RStudio Server after updating
    run_with_spinner "Starting RStudio Server" \
      "sudo systemctl start rstudio-server"
  else
    info_message "RStudio Server is not installed. Skipping RStudio Server update."
  fi
fi

# 5. Update VS Code and extensions
if [ "$UPDATE_ALL" = true ] || [ "$UPDATE_VSCODE" = true ]; then
  if command_exists code-server; then
    # Update code-server
    run_with_spinner "Updating VS Code (code-server)" \
      "curl -fsSL https://code-server.dev/install.sh | sh"

    # Update extensions
    run_with_spinner "Updating VS Code extensions" "
      code-server --install-extension ms-python.python --force && \
      code-server --install-extension ms-toolsai.jupyter --force && \
      code-server --install-extension quarto.quarto --force && \
      code-server --install-extension charliermarsh.ruff --force
    "
  else
    info_message "VS Code (code-server) is not installed. Skipping VS Code update."
  fi
fi

# 6. Update DuckDB
if [ "$UPDATE_ALL" = true ] || [ "$UPDATE_DUCKDB" = true ]; then
  if command_exists duckdb; then
    current_version=$(get_current_version "duckdb")
    info_message "Current DuckDB version: $current_version"
    info_message "Target DuckDB version: $DUCKDB_VERSION"

    if [ "$current_version" != "$DUCKDB_VERSION" ]; then
      run_with_spinner "Updating DuckDB to version $DUCKDB_VERSION" \
        "wget -q https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip && \
          unzip -o duckdb_cli-linux-amd64.zip && chmod +x duckdb && \
          sudo mv -f duckdb /usr/local/bin/ && rm duckdb_cli-linux-amd64.zip"
    else
      info_message "DuckDB is already at version $current_version. Skipping update."
    fi
  else
    info_message "DuckDB is not installed. Skipping DuckDB update."
  fi
fi

# 7. Update development tools
if [ "$UPDATE_ALL" = true ] || [ "$UPDATE_TOOLS" = true ]; then
  # Update Rust
  if [ -f "$HOME/.cargo/bin/rustup" ]; then
    run_with_spinner "Updating Rust" \
      "$HOME/.cargo/bin/rustup update"
  else
    info_message "Rust is not installed. Skipping Rust update."
  fi

  # Update uv and ruff
  if command_exists uv; then
    run_with_spinner "Updating uv" \
      "curl -LsSf https://astral.sh/uv/install.sh | sh"

    run_with_spinner "Updating ruff" \
      "uv tool install --upgrade ruff"
  else
    info_message "uv is not installed. Skipping uv/ruff update."
  fi

  # Update sqlfluff
  if command_exists sqlfluff; then
    run_with_spinner "Updating SQLFluff" \
      "uv tool install --upgrade sqlfluff"
  else
    info_message "SQLFluff is not installed. Skipping SQLFluff update."
  fi

  # Update rig
  if command_exists rig; then
    run_with_spinner "Updating rig" \
      "apt2 update && apt2 install -y r-rig"
  else
    info_message "rig is not installed. Skipping rig update."
  fi
fi

# Post-update message
echo ""
echo -e "${BOLD}${GREEN}Update complete!${RESET}"
echo -e "Log saved to: ${GREEN}${LOG_FILE}${RESET}"
echo ""
echo -e "${BOLD}Updated components:${RESET}"
if [ "$UPDATE_ALL" = true ]; then
  echo "  - All components have been checked and updated as needed"
else
  [ "$UPDATE_SYSTEM" = true ] && echo "  - System packages"
  [ "$UPDATE_R" = true ] && echo "  - R"
  [ "$UPDATE_QUARTO" = true ] && echo "  - Quarto"
  [ "$UPDATE_RSTUDIO" = true ] && echo "  - RStudio Server"
  [ "$UPDATE_VSCODE" = true ] && echo "  - VS Code and extensions"
  [ "$UPDATE_DUCKDB" = true ] && echo "  - DuckDB"
  [ "$UPDATE_TOOLS" = true ] && echo "  - Development tools (Rust, uv, ruff, sqlfluff, rig)"
fi
echo ""
echo -e "${BOLD}Note:${RESET} Unlike the setup script, no reboot is required."
echo "Services should continue running normally."
