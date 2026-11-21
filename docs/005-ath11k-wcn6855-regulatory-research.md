# Comprehensive Research: QCNFA765 (WCN6855) ath11k Self-Managed Regulatory Domain

**System:** Debian GNU/Linux 13 (trixie), kernel 6.12.117+deb13-amd64, x86_64
**Hardware:** Qualcomm QCNFA765 (WCN6855 hw2.1), PCI 17cb:1103, subsystem 105b:e0cc
**Driver:** ath11k_pci / ath11k, firmware WLAN.HSP.1.1-03125-QCAHSPSWPL_V1_V2_SILICONZ_LITE-3.6510.41
**Interface:** wlp1s0, managed by NetworkManager + wpa_supplicant
**iw installed:** Yes (6.9-1, from trixie main)

---

## 1. Observed Regulatory State (from `iw reg get` /usr/sbin/iw)

### Observation 1 — Domain ID (Indonesia, restricted)

```
global
country 00: DFS-UNSET
    (5735 - 5835 @ 80), (N/A, 20), (N/A), PASSIVE-SCAN

phy#0 (self-managed)
country ID: DFS-UNSET
    (2402 - 2482 @ 20), (N/A, 20), (N/A)
    (5735 - 5815 @ 20), (N/A, 20), (N/A), AUTO-BW
```

**5 GHz allowed: 5735–5815 MHz only (channels 149–161).** Channels 36–144 are blocked.

### Observation 2 — Domain US (FCC, full access) — CURRENT STATE

```
global
country 00: DFS-UNSET
    (5170 - 5250 @ 80), (N/A, 20), (N/A), AUTO-BW, PASSIVE-SCAN
    (5250 - 5330 @ 80), (N/A, 20), (0 ms), DFS, AUTO-BW, PASSIVE-SCAN
    (5490 - 5730 @ 160), (N/A, 20), (0 ms), DFS, PASSIVE-SCAN
    (5735 - 5835 @ 80), (N/A, 20), (N/A), PASSIVE-SCAN

phy#0 (self-managed)
country US: DFS-FCC
    (2402 - 2472 @ 40), (6, 30), (N/A)
    (5170 - 5250 @ 80), (N/A, 24), (N/A), AUTO-BW      <- ch 36-48
    (5250 - 5330 @ 80), (N/A, 24), (0 ms), DFS, AUTO-BW  <- ch 52-64
    (5490 - 5730 @ 160), (N/A, 24), (0 ms), DFS, AUTO-BW  <- ch 100-144
    (5735 - 5895 @ 160), (N/A, 30), (N/A), AUTO-BW       <- ch 149-165
    (5925 - 7125 @ 160), (N/A, 24), (N/A), NO-OUTDOOR, AUTO-BW  <- 6 GHz
```

**5 GHz allowed: 5170–5895 MHz (channels 36–165) + 6 GHz (5925–7125 MHz).**

**Active connection: `n34r-ih40p:wlp1s0`** — connected to Android hotspot on channel 36 (5180 MHz) with domain US.

### Critical Finding: Domain Changes Dynamically

The phy is `self-managed` (firmware-controlled), but the domain **changed between observations** — from `country ID` (restricted to ch 149–161) to `country US` (full 5 GHz + 6 GHz). The domain is NOT permanently locked.

---

## 2. Why the Domain Changes Dynamically

Three kernel mechanisms enable regulatory domain changes on self-managed WCN6855 phys:

### 2.1 11d Scan Offload (kernel patch Nov 2021)

The firmware performs periodic 11d offload scans, picking up country information elements from nearby AP beacons. This drives:
```
WMI_11D_NEW_COUNTRY_EVENTID → ath11k_reg_set_cc() → WMI_REG_CHAN_LIST_CC_EVENTID → ath11k_regd_update_work()
```

Source: `ath11k: add 11d scan offload support for QCA6390/WCN6855` (Nov 2021)

### 2.2 CVE-2025-23133 Fix (kernel 6.12.48+, Debian trixie 6.12.117)

Added `WIPHY_FLAG_NOTIFY_REGDOM_BY_DRIVER` flag. This makes `reg_process_self_managed_hint()` call `reg_call_notifier()` when the flag is set, allowing self-managed phys to receive regulatory domain updates through the driver notifier path.

Debian security tracker: trixie 6.12.117-1 → **fixed**. User's kernel: 6.12.117+deb13-amd64 → **includes the fix.**

Source: CVE-2025-23133 SRU patch (September 2026), Debian DSA-6008-1

### 2.3 Suspend/Resume Country Restore (kernel May 2024)

Restores country code to firmware during resume, because firmware reinitialization loses the previously set domain.

Source: `wifi: ath11k: restore country code during resume` (May 2024)

### Most Likely Explanation for Home vs Work Difference

**802.11d beacon country announcement:**

- **At home:** Nearby APs (possibly including the user's own Android hotspot) broadcast US country code → firmware's 11d offload scan picks it up → domain becomes US → channels 36–165 visible → hotspot on ch 36 connectable ✅
- **At work:** Nearby APs broadcast ID country code or no country code → domain stays at or defaults to ID → channels 36–144 blocked → hotspot on ch 36 invisible ❌

This is the most plausible explanation for why the same phone's hotspot works at home but not at work.

---

## 3. What Does NOT Work (Confirmed by Research)

| Approach | Result | Source |
|----------|--------|--------|
| `iw reg set <COUNTRY>` | Rejected by firmware (-22), no effect | Arch Linux Forum 2026-10-09 |
| `WIRELESS_REGDOM` config | Ignored | Arch Linux Forum 2026-10-09 |
| Editing `board-2.bin` regDmn field | Always 0, comes from chip OTP, no effect | Arch Linux Forum 2026-10-09 |
| Editing `regdb.bin` | Firmware crash `MHI_CB_EE_RDDM` | Arch Linux Forum 2026-10-09 |
| CRDA / `wireless-regdb` updates | Ignored for self-managed phys | ath11k regdb offload patch (2021-12) |

---

## 4. What MAY Work

### 4.1 SMBIOS Country Code Patch (Kernel-Level)

Patch: `ath11k: add read country code from SMBIOS for WCN6855/QCA6390` (April 2022).

- Reads country code from laptop SMBIOS and sends it to firmware.
- Requires kernel config `CONFIG_ATH_REG_DYNAMIC_USER_REG_HINTS`.
- **Status on this system: NOT enabled.** `grep` of `/boot/config-6.12.116+deb13-amd64` returned 0 matches for `ATH_REG_DYNAMIC`.

SMBIOS country code encoding:
- `ATH11K_SMBIOS_CC_ISO = 1` — e.g., US = 0x5553, ID = 0x4944
- `ATH11K_SMBIOS_CC_WW = 2` — worldwide regdomain

### 4.2 Firmware Update (firmware-atheros)

Newer upstream `linux-firmware` may resolve regional database bugs for WCN6855.

- Arch Linux `linux-firmware-atheros 20261019-1` includes WCN6855 hw2.0 and hw2.1 regdb.bin.
- nfa765 firmware variant exists but is for IOE devices, not standard laptops.

### 4.3 Host-Side ath11k Patch (DKMS)

`ath11k-ru` DKMS module patches `ath11k/reg.c` to modify regulatory rules on the host side. Currently only demonstrated for 2.4 GHz channels 12-13. No published patch for 5 GHz extension.

---

## 5. Firmware File Structure (board-2.bin and regdb.bin)

The `ath11k-bdencoder` tool (Qualcomm qca-swiss-army-knife) manages board-N.bin container format:

- Signature: `QCA-ATH11K-BOARD` (20 bytes)
- Contains IEs: `ATH11K_BD_IE_BOARD` (type 0) and `ATH11K_BD_IE_REGDB` (type 1)
- regdb.bin inside board-2.bin contains the regulatory rules the firmware uses

### WCN6855 hw2.1 has `current_cc_support = true`

Patch `ath11k: avoid firmware crash when reg set for QCA6390/WCN6855` (Jan 2022) added `current_cc_support = true` for wcn6855 hw2.0 and hw2.1, and changed reg.c to use `WMI_SET_CURRENT_COUNTRY_CMDID` instead of `WMI_SET_INIT_COUNTRY_CMDID` for station-based chips (avoiding firmware crash).

This means: **the driver DOES support setting country code on WCN6855 hw2.1** via the proper WMI command. The limitation is at the kernel config level (`CONFIG_ATH_REG_DYNAMIC_USER_REG_HINTS` not enabled).

---

## 6. Debian-Specific Situation

| Item | Status |
|------|--------|
| Kernel | 6.12.117+deb13-amd64 |
| CVE-2025-23133 fix | **Fixed** (6.12.117-1, DSA-6008-1) |
| `CONFIG_ATH_REG_DYNAMIC_USER_REG_HINTS` | **Not enabled** (0 matches in kernel config) |
| `iw` installed | Yes (6.9-1) |
| `CONFIG_ATH_REG_DYNAMIC_USER_REG_HINTS` needed for SMBIOS patch | Not present |
| Driver supports `WMI_SET_CURRENT_COUNTRY_CMDID` on WCN6855 hw2.1 | Yes (`current_cc_support = true`) |

---

## 7. Summary of Options for the User

### Immediate Workarounds (no kernel rebuild)

| Option | Viability | Notes |
|--------|-----------|-------|
| Use Android hotspot on 5 GHz channels 149–161 only | Works if phone allows channel selection | Only works when domain is ID |
| Use Android hotspot on 2.4 GHz | Works reliably | Slower but always visible |
| USB tethering | Bypasses WiFi entirely, most stable | Recommended for work |
| Check domain before connecting | `iw reg get` → if US, ch 36 works; if ID, only ch 149–161 | Quick diagnostic |

### Advanced / Risky Options

| Option | Risk | Feasibility |
|--------|------|-------------|
| Rebuild kernel with `CONFIG_ATH_REG_DYNAMIC_USER_REG_HINTS=y` + SMBIOS patch | Medium | Requires kernel build expertise |
| DKMS patch of ath11k reg.c for 5 GHz rule extension | Medium | No published patch for 5 GHz |
| Modify regdb.bin (custom) | High — firmware crash risk | Trailer format undocumented |

### Not Recommended

- Editing regdb.bin manually — causes `MHI_CB_EE_RDDM` firmware crash
- Editing board-2.bin regDmn — always 0, no effect
- Expecting `iw reg set` to work — rejected by firmware on self-managed phys

---

## 8. Evidence Files Created

| File | Purpose |
|------|---------|
| `devices/ath11k-5ghz-fix/ath11k-5ghz-fix` | Fix script (reloads driver, restarts NM, disables power-save) |
| `devices/ath11k-5ghz-fix/ath11k-5ghz-fix.service` | systemd unit |
| `devices/ath11k-5ghz-fix/ath11k-5ghz-fix.timer` | systemd timer (every 5 min) |
| `devices/ath11k-5ghz-fix/README.md` | Usage instructions |
| `docs/005-ath11k-wcn6855-regulatory-research.md` | This research document |
| `docs/004.md` | Prior troubleshooting doc (contains inaccuracies: references bookworm instead of trixie) |

---

## References

1. Linux kernel ath11k driver docs: https://wireless.docs.kernel.org/en/latest/en/users/drivers/ath11k.html
2. ath11k reg.c source: https://codebrowser.dev/linux/linux/drivers/net/wireless/ath/ath11k/reg.c.html
3. Arch Linux Forum workaround (2026-10-09): https://bbs.archlinux.org/viewtopic.php?id=315152
4. SMBIOS country code patch (2022-04): http://lists.infradead.org/pipermail/ath11k/2022-April/003021.html
5. regdb offload patch (2021-12): http://lists.infradead.org/pipermail/ath11k/2021-December/002400.html
6. 11d scan offload patch (2021-11): http://lists.infradead.org/pipermail/ath11k/2021-November/002005.html
7. Firmware crash fix for WCN6855 reg set (2022-01): http://lists.infradead.org/pipermail/ath11k/2022-January/002547.html
8. Suspend/resume country restore (2024-05): http://lists.infradead.org/pipermail/ath11k/2024-May/005902.html
9. CVE-2025-23133 fix (2026-09): https://lists.ubuntu.com/archives/kernel-team/2026-September/171715.html
10. Debian security tracker CVE-2025-23133: https://security-tracker.debian.org/tracker/CVE-2025-23133
11. qca-swiss-army-knife bdencoder: https://github.com/qca/qca-swiss-army-knife
12. Cisco Indonesia regulatory domains: https://www.cisco.com/c/en/us/td/docs/wireless/controller/technotes/reg-domain/reg-domain-rule-changes-in-810MR3-and-17-3.html
13. Debian 13 trixie release: https://www.debian.org/News/2025/20250809