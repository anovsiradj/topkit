# ath11k-5ghz-fix

Fix intermittent "5 GHz not detected" on Qualcomm **QCNFA765** (WCN6855) with the `ath11k_pci` driver on Debian.

## Problem

The QCNFA765 card uses a **self-managed regulatory domain** controlled by its firmware. The domain can change dynamically:

- **country ID (Indonesia):** Only 5 GHz channels 149–161 (5735–5815 MHz) are allowed. Channels 36–144 are blocked.
- **country US (FCC):** Full 5 GHz channels 36–165 + 6 GHz are allowed.

The domain switches based on 802.11d country beacons detected by the firmware's 11d scan offload. This is the most likely reason your Android hotspot works at home (domain US, ch 36 visible) but not at work (domain may be ID, ch 36 invisible).

Current state on this system:
```
phy#0 (self-managed)
country US: DFS-FCC
    (5170 - 5250 @ 80), ...   <- ch 36-48
    (5250 - 5330 @ 80), ...   <- ch 52-64
    (5490 - 5730 @ 160), ...  <- ch 100-144
    (5735 - 5895 @ 160), ...  <- ch 149-165
    (5925 - 7125 @ 160), ...  <- 6 GHz
```

Active connection: `n34r-ih40p:wlp1s0` — connected to Android hotspot on **channel 36 (5180 MHz)** with domain US.

## What this tool does

1. Checks whether any 5 GHz SSID is visible via `nmcli`.
2. If none, reloads the `ath11k_pci` driver and restarts `NetworkManager` (fixes intermittent 5 GHz dropouts).
3. Disables Wi-Fi power save so the radio stays awake on 5 GHz.
4. (`status` mode only) Reports the actual allowed 5 GHz range and domain from `iw reg get`.

## Files

| File | Purpose |
|------|---------|
| `ath11k-5ghz-fix` | Main script (executable) |
| `ath11k-5ghz-fix.service` | systemd oneshot unit |
| `ath11k-5ghz-fix.timer` | systemd timer (runs fix every 5 min) |
| `README.md` | This file |

## Usage

### One-shot fix (run when 5 GHz disappears)

```sh
chmod +x devices/ath11k-5ghz-fix/ath11k-5ghz-fix
sudo ./devices/ath11k-5ghz-fix/ath11k-5ghz-fix fix
```

### Check current state (domain + 5 GHz visibility)

```sh
sudo ./devices/ath11k-5ghz-fix/ath11k-5ghz-fix status
```

### Auto-fix loop (watch until 5 GHz returns)

```sh
sudo ./devices/ath11k-5ghz-fix/ath11k-5ghz-fix --watch
```

### Automatic fix every 5 minutes (systemd timer)

```sh
sudo cp devices/ath11k-5ghz-fix/ath11k-5ghz-fix.service /etc/systemd/system/
sudo cp devices/ath11k-5ghz-fix/ath11k-5ghz-fix.timer /etc/systemd/system/
sudo systemctl enable --now ath11k-5ghz-fix.timer
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WIFI_IFACE` | `wlp1s0` | WiFi interface name |
| `WIFI_REGDOM` | `US` | Regulatory domain to attempt (best-effort; often ignored on self-managed phys) |
| `WIFI_FIX_LOG` | `/var/log/ath11k-5ghz-fix.log` | Log file path |

Example:

```sh
sudo WIFI_REGDOM=US ./devices/ath11k-5ghz-fix/ath11k-5ghz-fix fix
```

## Important limitations

- **This cannot force a specific regulatory domain.** The domain is firmware-controlled and changes dynamically via 802.11d beacons. `iw reg set` has no effect on self-managed phys.
- If your domain is `country ID`, your laptop cannot see 5 GHz channels 36–144. Your Android hotspot must be on channel 149–161 to be visible.
- If your domain is `country US`, all 5 GHz channels 36–165 are visible.
- **Workarounds for Android hotspot:** set your phone's hotspot to **2.4 GHz**, use **USB tethering**, or set the hotspot to 5 GHz **channels 149–165** if your phone allows it.
- This script **does** fix intermittent 5 GHz dropouts on channels your card *can* use.

## Diagnostic: check why your hotspot is invisible

```sh
# Check current regulatory domain
/usr/sbin/iw reg get

# Check your active connection's channel
nmcli -t -f NAME,DEVICE connection show --active

# Scan for your hotspot's frequency
nmcli device wifi rescan
nmcli -t -f SSID,FREQ device wifi list | grep -i "your-hotspot-name"
```

If `iw reg get` shows `country ID` with only 5735–5815 MHz, and your hotspot is on channel 36–144, that's why it's invisible. Change your hotspot to channel 149–161 or use 2.4 GHz / USB tethering.

## Requirements

- `nmcli` (NetworkManager CLI)
- `modprobe`, `systemctl` (root)
- `iw` (installed at `/usr/sbin/iw` on Debian 13)
