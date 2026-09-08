#!/usr/bin/env bash
set -euo pipefail

cd .. && wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.9-stable.tar.xz && tar -xf flutter_linux_3.44.9-stable.tar.xz && rm flutter_linux_3.44.9-stable.tar.xz

echo "OK"