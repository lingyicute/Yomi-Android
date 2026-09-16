#!/usr/bin/env bash
set -euo pipefail

cd .. && wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.4-stable.tar.xz && tar -xf flutter_linux_3.47.4-stable.tar.xz && rm flutter_linux_3.47.4-stable.tar.xz

echo "OK"