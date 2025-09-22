#!/bin/bash

# Check installed tools
echo "=== Checking installations ==="
which python3 && python3 --version
which R && R --version | head -1
which quarto && quarto --version
which rstudio-server && rstudio-server version | head -1
which code-server && code-server --version | head -1
which duckdb && duckdb --version
which uv && uv --version
which ruff && ruff --version
which sqlfluff && sqlfluff --version
which gh && gh --version
which rig && rig --version
which rustc && rustc --version
which pandoc && pandoc --version | head -1
which docker && docker --version && docker compose version

# Check services
echo -e "\n=== Checking services ==="
systemctl is-active rstudio-server
systemctl is-active code-server@$USER
systemctl is-active docker
