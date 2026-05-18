#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="razer-hid-tool"
VENDOR_ID="0x1532"
PRODUCT_ID="0x0084"

usage() {
  cat >&2 <<USAGE
usage: $0 [--raw|--special|--list] [extra razer-hid-tool args...]

DeathAdder V2 debug helpers:
  --raw          Listen to all HID interfaces/events for the mouse. Default.
  --special      Print only the four target buttons: F15, F16, side usage 0x04, side usage 0x05.
  --list         List matching DeathAdder HID interfaces.
USAGE
}

MODE="--raw"
if [[ $# -gt 0 ]]; then
  case "$1" in
    --raw|raw)
      MODE="--raw"
      shift
      ;;
    --special|special)
      MODE="--special"
      shift
      ;;
    --list|list)
      MODE="--list"
      shift
      ;;
    --help|-h|help)
      usage
      exit 0
      ;;
  esac
fi

cd "$ROOT_DIR"

case "$MODE" in
  --raw)
    exec swift run "$PRODUCT_NAME" --probe-all-interfaces --vendor-id "$VENDOR_ID" --product-id "$PRODUCT_ID" "$@"
    ;;
  --special)
    swift build --product "$PRODUCT_NAME"
    echo "Listening for special buttons only. Press Ctrl+C to exit"
    exec "$ROOT_DIR/.build/debug/$PRODUCT_NAME" --deathadder-v2-buttons-listen "$@"
    ;;
  --list)
    exec swift run "$PRODUCT_NAME" --list --vendor-id "$VENDOR_ID" --product-id "$PRODUCT_ID" --all-devices "$@"
    ;;
  *)
    usage
    exit 2
    ;;
esac
