#!/usr/bin/env bash
set -euo pipefail

if [[ -e /proc/sys/net/mpls/platform_labels ]]; then
  echo "MPLS kernel forwarding support: PASS"
  exit 0
fi

kernel_config=""
if [[ -r /proc/config.gz ]] && command -v zgrep >/dev/null 2>&1; then
  kernel_config="$(zgrep -E \
    '^(CONFIG_MPLS_ROUTING=|# CONFIG_MPLS_ROUTING is not set)' \
    /proc/config.gz || true)"
elif [[ -r "/boot/config-$(uname -r)" ]]; then
  kernel_config="$(grep -E \
    '^(CONFIG_MPLS_ROUTING=|# CONFIG_MPLS_ROUTING is not set)' \
    "/boot/config-$(uname -r)" || true)"
fi

echo "ERROR: Linux MPLS forwarding support is unavailable." >&2
if [[ -n "$kernel_config" ]]; then
  echo "Kernel configuration: ${kernel_config}" >&2
fi
cat >&2 <<'EOF'

The MPLS L3VPN lab requires a kernel with at least:
  CONFIG_MPLS_ROUTING=y|m
  CONFIG_MPLS_IPTUNNEL=y|m
  CONFIG_NET_MPLS_GSO=y|m
  CONFIG_NET_VRF=y|m

These options may also be built as modules. In that case, install the matching
kernel modules and load mpls_router, mpls_iptunnel, mpls_gso, and vrf before
deploying. A WSL2 installation whose kernel sets CONFIG_MPLS_ROUTING=n needs
an MPLS-capable custom WSL kernel or a Linux VM/host.
EOF
exit 1
