#!/bin/bash

# Define colors and text styles
BOLD=$(tput bold)
RESET=$(tput sgr0)
GREEN=$(tput setaf 2)

# Define the log file location
LOG_FILE="/tmp/setup_log.txt"

# Initialize the log file
echo "Starting setup..." > "$LOG_FILE"

# Helper functions for displaying progress
function display_message() {
  echo -n "${BOLD}$1${RESET}...  "
}

function complete_message() {
  echo -e "${GREEN}Done.${RESET}"
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
  echo -ne "\b"
}

# Run a command with spinner
function run_with_spinner() {
  display_message "$1"
  eval "$2" >> "$LOG_FILE" 2>&1 & spinner
  complete_message
}

# Define a custom apt function to enforce DEBIAN_FRONTEND
function apt_install() {
  sudo DEBIAN_FRONTEND=noninteractive apt "$@"
}

# Define software versions
QUARTO_VERSION=${QUARTO_VERSION:-"1.5.57"}
RSTUDIO_SERVER_VERSION=${RSTUDIO_SERVER_VERSION:-"2024.09.0-375"}
DUCKDB_VERSION=${DUCKDB_VERSION:-"0.8.1"}

# 1. Update and upgrade packages
run_with_spinner "Updating and upgrading OS packages" \
  "apt_install update && apt_install upgrade -y"

# 2. Install essential packages for handling repositories and dependencies
run_with_spinner "Installing essential packages for repositories and dependencies" \
  "apt_install install -y software-properties-common gdebi-core unzip"

# 3. Install common system libraries for R, Python, and data science packages
run_with_spinner "Installing common system libraries" \
  "apt_install install -y \
    wget curl git libssl-dev libxml2-dev libgit2-dev \
    build-essential libclang-dev libgmp3-dev libglpk40 \
    libharfbuzz-dev libfribidi-dev libicu-dev libxml2 \
    libpng-dev libjpeg-dev libtiff5-dev libfontconfig1-dev \
    libfreetype-dev libcairo2-dev libxt-dev libmagick++-dev \
    libsqlite3-dev libmariadb-dev libpq-dev unixodbc-dev \
    gdal-bin libgeos-dev libproj-dev \
    zlib1g-dev libbz2-dev liblzma-dev libpcre2-dev perl"

# 4. Add the CRAN repository for R
run_with_spinner "Adding Ubuntu repository for R" \
  "sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys \
    E298A3A825C0D65DFD57CBB651716619E084DAB9 && \
    sudo add-apt-repository -y 'deb https://cloud.r-project.org/bin/linux/ubuntu \
    $(lsb_release -cs)-cran40/'"

# 5. Install the latest version of R
run_with_spinner "Installing R" "apt_install install -y r-base r-base-dev"

# 6. Configure CRAN mirror for R to use Posit Public Package Manager
run_with_spinner "Configuring CRAN mirror for R to use Posit Public Package Manager" \
  "sudo mkdir -p /etc/R && echo 'options(repos = c(CRAN = \
    \"https://packagemanager.posit.co/cran/__linux__/noble/latest\"))' | \
    sudo tee /etc/R/Rprofile.site"

# 7. Install latest Python version
run_with_spinner "Installing Python" "apt_install install -y python3 python3-pip python3.12-venv"

# 8. Configure pip to use Posit Public Package Manager
run_with_spinner "Configuring pip to use Posit Public Package Manager" \
  "sudo pip config set --global global.index-url \
    https://packagemanager.posit.co/pypi/latest/simple && \
    sudo pip config set --global global.trusted-host packagemanager.posit.co"

# 9. Install Quarto
run_with_spinner "Installing Quarto" \
  "wget https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/\
    quarto-${QUARTO_VERSION}-linux-amd64.deb && sudo dpkg -i \
    quarto-${QUARTO_VERSION}-linux-amd64.deb && rm quarto-${QUARTO_VERSION}-linux-amd64.deb"

# 10. Install Miniconda
run_with_spinner "Installing Miniconda" \
  "wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh && \
    chmod +x Miniconda3-latest-Linux-x86_64.sh && ./Miniconda3-latest-Linux-x86_64.sh -b \
    -p $HOME/miniconda && rm Miniconda3-latest-Linux-x86_64.sh && \
    echo 'export PATH=\"$HOME/miniconda/bin:\$PATH\"' >> ~/.bashrc && \
    source ~/.bashrc"

# 11. Install TinyTeX for LaTeX support
run_with_spinner "Installing TinyTeX" "wget -qO- 'https://yihui.org/tinytex/install-bin-unix.sh' | sh"

# 12a. Install RStudio Server
run_with_spinner "Installing RStudio Server" \
  "wget https://download2.rstudio.org/server/jammy/amd64/rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb && \
    sudo gdebi -n rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb && \
    rm rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb"

# 12b. Tweak default RStudio Server settings
run_with_spinner "Updating RStudio Server preferences" \
  'PREFERENCES='"'"'{
    "insert_native_pipe_operator": true,
    "save_workspace": "never",
    "load_workspace": "never",
    "rainbow_parentheses": true,
    "rainbow_fenced_divs": true
  }'"'"'; TARGET_FILE="/etc/rstudio/rstudio-prefs.json"; echo "$PREFERENCES" | sudo tee "$TARGET_FILE" > /dev/null'


# 13. Install VS Code (code-server)
run_with_spinner "Installing VS Code" \
  "curl -fsSL https://code-server.dev/install.sh | sh && sudo systemctl enable --now code-server@$USER"

# 14. Install GitHub CLI
run_with_spinner "Installing GitHub CLI" \
  "(type -p wget >/dev/null || (apt_install update && apt_install install wget -y)) && \
    sudo mkdir -p -m 755 /etc/apt/keyrings && wget -qO- \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main' | \
    sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt_install update && apt_install install gh -y"

# 15. Install DuckDB CLI
run_with_spinner "Installing DuckDB CLI" \
  "wget https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip && \
    unzip duckdb_cli-linux-amd64.zip && chmod +x duckdb && \
    sudo mv duckdb /usr/local/bin/ && rm duckdb_cli-linux-amd64.zip"

# 16. Install Rust
run_with_spinner "Installing Rust" \
  "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    echo 'export PATH=\"$HOME/.cargo/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"

# 17. Install uv
run_with_spinner "Installing uv" "curl -LsSf https://astral.sh/uv/install.sh | sh"

# Set default git branch to main
run_with_spinner "Setting default Git branch to main" "git config --global init.defaultBranch main"

# Post-install message
echo -e "\n${BOLD}Installation complete!${RESET} Log saved to ${GREEN}${LOG_FILE}${RESET}."
echo "${BOLD}Installed tools${RESET}: R, Python, Quarto, RStudio Server, VS Code, DuckDB, Miniconda, Rust, uv"
echo -e "${BOLD}To finalize setup:${RESET} open a new terminal or log out and back in to update paths."
echo -e "${BOLD}Forward ports for RStudio Server (8787) and VS Code (8080) with${RESET}:
  '${GREEN}gcloud compute ssh --zone \"\$ZONE\" \"\$INSTANCE_NAME\" --project \"\$PROJECT_ID\" -- -L 8787:localhost:8787 -L 8080:localhost:8080${RESET}'"
