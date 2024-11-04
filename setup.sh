#!/bin/bash
# Add to crontab for immediate execution after reboot
(crontab -l ; echo "@reboot bash \"$0\"") | crontab -
MARKER_FILE="/tmp/.setup_completed"

# Define software versions
# R_VERSION=${R_VERSION:-"4.4.0"}
QUARTO_VERSION=${QUARTO_VERSION:-"1.5.57"}
RSTUDIO_SERVER_VERSION=${RSTUDIO_SERVER_VERSION:-"2024.09.0-375"}
DUCKDB_VERSION=${DUCKDB_VERSION:-"0.8.1"}

## setup
if [[ ! -f "$MARKER_FILE" ]]; then
  touch "$MARKER_FILE"

  # Update and upgrade packages
  sudo apt update && sudo apt upgrade -y

  # Install essential packages for handling repositories and dependencies
  sudo apt install -y software-properties-common gdebi-core unzip

  # Install common system libraries for R, Python, and data science packages
  sudo apt install -y \
      wget curl git libssl-dev libxml2-dev libgit2-dev \
      build-essential libclang-dev libgmp3-dev libglpk40 \
      libharfbuzz-dev libfribidi-dev libicu-dev libxml2 \
      libpng-dev libjpeg-dev libtiff5-dev libfontconfig1-dev \
      libfreetype-dev libcairo2-dev libxt-dev libmagick++-dev \
      libsqlite3-dev libmariadb-dev libpq-dev unixodbc-dev \
      gdal-bin libgeos-dev libproj-dev \
      zlib1g-dev libbz2-dev liblzma-dev libpcre2-dev perl

  # Add the CRAN repository for R
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E298A3A825C0D65DFD57CBB651716619E084DAB9
  sudo add-apt-repository -y "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"

  # Install the latest version of R
  sudo apt-get install -y r-base r-base-dev

else
  echo "NOTE: continuing process post-setup"
fi

# Create `Rprofile.site` to set CRAN mirror if it doesn’t exist
# Then use Posit Public Package Manager for package binaries
sudo mkdir -p /etc/R
echo 'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest"))' | sudo tee /etc/R/Rprofile.site

# Install latest Python version
sudo apt install -y python3 python3-pip python3.12-venv

# Use Posit Public Package Manager for package binaries with pip
sudo pip config set --global global.index-url https://packagemanager.posit.co/pypi/latest/simple
sudo pip config set --global global.trusted-host packagemanager.posit.co

# Install Quarto with specified version
wget https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.deb
sudo dpkg -i quarto-${QUARTO_VERSION}-linux-amd64.deb
rm quarto-${QUARTO_VERSION}-linux-amd64.deb

# Install Miniconda and add to PATH
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
chmod +x Miniconda3-latest-Linux-x86_64.sh
./Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda
rm Miniconda3-latest-Linux-x86_64.sh
echo "export PATH=\"$HOME/miniconda/bin:\$PATH\"" | sudo tee -a /etc/profile.d/miniconda.sh
source /etc/profile.d/miniconda.sh

# Install TinyTeX for LaTeX support in Quarto
wget -qO- "https://yihui.org/tinytex/install-bin-unix.sh" | sh

# Install RStudio Server with specified version
wget https://download2.rstudio.org/server/jammy/amd64/rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb
sudo gdebi -n rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb
rm rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb

# Install VS Code (code-server), latest version
curl -fsSL https://code-server.dev/install.sh | sh
sudo systemctl enable --now code-server@$USER

# Install gh command line tool for GitHub, latest version
(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y

# Install DuckDB CLI with specified version
wget https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip
unzip duckdb_cli-linux-amd64.zip
chmod +x duckdb
sudo mv duckdb /usr/local/bin/
rm duckdb_cli-linux-amd64.zip

# Install Rust using rustup and add to PATH
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
echo "source $HOME/.cargo/env" | sudo tee -a /etc/profile.d/rust.sh
source /etc/profile.d/rust.sh

# Install uv, latest version
curl -LsSf https://astral.sh/uv/install.sh | sh

# set default branch to main
git config --global init.defaultBranch main

# Remove cron job
crontab -l | grep -v "@reboot bash \"$0\"" | crontab -

# Remove marker file
rm "$MARKER_FILE"

# Post-install message
echo "Installation complete! R, Python, Quarto, RStudio Server, VS Code (code-server), DuckDB, conda, Rust, and uv are installed."
echo "To finalize setup, open a new terminal or log out and back in to ensure all paths are updated."
echo "And forward the ports for RStudio Server (8787) and VS Code (8080) with 'gcloud ... -- -L 8787:localhost:8787 -L 8080:localhost:8080'."
echo "TODO: 1) setup a user for RStudio with 'sudo adduser your_username' 2) login to GitHub with 'gh auth login'"
