#!/bin/bash

# Define colors and text styles
BOLD=$(tput bold)
RESET=$(tput sgr0)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)

# Define the log file location
LOG_FILE="/tmp/setup_log.txt"

# Initialize the log file
echo "Starting setup..." > "$LOG_FILE"

# Helper functions for displaying progress
function display_message() {
  echo -n "${BOLD}$1${RESET}..."
}

function complete_message() {
  echo -e "${GREEN}Done.${RESET}"
}

# Add to crontab for immediate execution after reboot
(crontab -l ; echo "@reboot bash \"$0\"") | crontab -

# Define software versions
QUARTO_VERSION=${QUARTO_VERSION:-"1.5.57"}
RSTUDIO_SERVER_VERSION=${RSTUDIO_SERVER_VERSION:-"2024.09.0-375"}
DUCKDB_VERSION=${DUCKDB_VERSION:-"0.8.1"}

# 1. Update and upgrade packages
display_message "Updating and upgrading OS packages"
sudo apt update >> "$LOG_FILE" 2>&1 && sudo apt upgrade -y >> "$LOG_FILE" 2>&1
complete_message

# 2. Install essential packages for handling repositories and dependencies
display_message "Installing essential packages for repositories and dependencies"
sudo apt install -y software-properties-common gdebi-core unzip >> "$LOG_FILE" 2>&1
complete_message

# 3. Install common system libraries for R, Python, and data science packages
display_message "Installing common system libraries"
sudo apt install -y \
    wget curl git libssl-dev libxml2-dev libgit2-dev \
    build-essential libclang-dev libgmp3-dev libglpk40 \
    libharfbuzz-dev libfribidi-dev libicu-dev libxml2 \
    libpng-dev libjpeg-dev libtiff5-dev libfontconfig1-dev \
    libfreetype-dev libcairo2-dev libxt-dev libmagick++-dev \
    libsqlite3-dev libmariadb-dev libpq-dev unixodbc-dev \
    gdal-bin libgeos-dev libproj-dev \
    zlib1g-dev libbz2-dev liblzma-dev libpcre2-dev perl >> "$LOG_FILE" 2>&1
complete_message

# 4. Add the CRAN repository for R
display_message "Adding CRAN repository for R"
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9 >> "$LOG_FILE" 2>&1
sudo add-apt-repository -y "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" >> "$LOG_FILE" 2>&1
complete_message

# 5. Install the latest version of R
display_message "Installing R"
sudo apt-get install -y r-base r-base-dev >> "$LOG_FILE" 2>&1
complete_message

# 6. Configure CRAN mirror for R
display_message "Configuring CRAN mirror for R"
sudo mkdir -p /etc/R
echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"))' | sudo tee /etc/R/Rprofile.site >> "$LOG_FILE" 2>&1
complete_message

# 7. Install latest Python version
display_message "Installing Python"
sudo apt install -y python3 python3-pip python3.12-venv >> "$LOG_FILE" 2>&1
complete_message

# 8. Configure pip to use Posit Public Package Manager
display_message "Configuring pip to use Posit package manager"
sudo pip config set --global global.index-url https://packagemanager.posit.co/pypi/latest/simple >> "$LOG_FILE" 2>&1
sudo pip config set --global global.trusted-host packagemanager.posit.co >> "$LOG_FILE" 2>&1
complete_message

# 9. Install Quarto
display_message "Installing Quarto"
wget https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb >> "$LOG_FILE" 2>&1
sudo dpkg -i quarto-${QUARTO_VERSION}-linux-amd64.deb >> "$LOG_FILE" 2>&1
rm quarto-${QUARTO_VERSION}-linux-amd64.deb
complete_message

# 10. Install Miniconda
display_message "Installing Miniconda"
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh >> "$LOG_FILE" 2>&1
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda >> "$LOG_FILE" 2>&1
rm Miniconda3-latest-Linux-x86_64.sh
echo "export PATH=\"$HOME/miniconda/bin:\$PATH\"" | sudo tee -a /etc/profile.d/miniconda.sh >> "$LOG_FILE" 2>&1
source /etc/profile.d/miniconda.sh
complete_message

# 11. Install TinyTeX for LaTeX support
display_message "Installing TinyTeX for LaTeX support"
wget -qO- "https://yihui.org/tinytex/install-bin-unix.sh" | sh >> "$LOG_FILE" 2>&1
complete_message

# 12. Install RStudio Server
display_message "Installing RStudio Server"
wget https://download2.rstudio.org/server/jammy/amd64/rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb >> "$LOG_FILE" 2>&1
sudo gdebi -n rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb >> "$LOG_FILE" 2>&1
rm rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb
complete_message

# 13. Install VS Code (code-server)
display_message "Installing VS Code (code-server)"
curl -fsSL https://code-server.dev/install.sh | sh >> "$LOG_FILE" 2>&1
sudo systemctl enable --now code-server@$USER >> "$LOG_FILE" 2>&1
complete_message

# 14. Install GitHub CLI
display_message "Installing GitHub CLI"
(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) >> "$LOG_FILE" 2>&1
sudo mkdir -p -m 755 /etc/apt/keyrings
wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update >> "$LOG_FILE" 2>&1 && sudo apt install gh -y >> "$LOG_FILE" 2>&1
complete_message

# 15. Install DuckDB CLI
display_message "Installing DuckDB CLI"
wget https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip >> "$LOG_FILE" 2>&1
unzip duckdb_cli-linux-amd64.zip >> "$LOG_FILE" 2>&1
chmod +x duckdb
sudo mv duckdb /usr/local/bin/
rm duckdb_cli-linux-amd64.zip
complete_message

# 16. Install Rust
display_message "Installing Rust"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >> "$LOG_FILE" 2>&1
echo "source $HOME/.cargo/env" | sudo tee -a /etc/profile.d/rust.sh >> "$LOG_FILE" 2>&1
source /etc/profile.d/rust.sh
complete_message

# 17. Install uv
display_message "Installing uv"
curl -LsSf https://astral.sh/uv/install.sh | sh >> "$LOG_FILE" 2>&1
complete_message

# Set default git branch to main
display_message "Setting default Git branch to main"
git config --global init.defaultBranch main >> "$LOG_FILE" 2>&1
complete_message

# Remove cron job
display_message "Removing cron job"
crontab -l | grep -v "@reboot bash \"$0\"" | crontab - >> "$LOG_FILE" 2>&1
complete_message

# Post-install message
echo -e "\n${BOLD}Installation complete!${RESET} Log saved to ${LOG_FILE}."
echo "Installed tools: R, Python, Quarto, RStudio Server, VS Code, DuckDB, Miniconda, Rust, uv"
echo -e "${YELLOW}To finalize setup:${RESET} open a new terminal or log out and back in to update paths."
echo -e "Forward ports for RStudio Server (8787) and VS
