# MyWhoosh for Linux

**Ride [MyWhoosh](https://mywhoosh.com) on Linux with one command.** Free indoor cycling, full
Bluetooth trainer support, automatic game updates, and a setup that keeps starting tomorrow the
way it did today.

```sh
curl -fsSL https://raw.githubusercontent.com/Parapeth962/mywhoosh-linux-installer/main/install.sh | bash
```

Answer two questions (regular or HD, how your trainer connects), type your password once, and
wait for the download. A **MyWhoosh** icon appears on your desktop or in your application menu.

## Why this one

- **It keeps launching.** The usual Wine/Lutris recipes start once and then refuse to open. The
  cause: MyWhoosh installs Apple's Bonjour service on first start, and from then on its network
  code calls a COM feature that wine-mono does not implement, so the game crashes before any
  window appears. This installer stops Bonjour from ever being installed and refuses to start a
  prefix that has it.
- **Updates itself.** MyWhoosh updates through the Microsoft Store, which Linux does not have.
  Every launch compares your version with the Store's and, if a newer one exists, downloads it
  first, swapping it in only once it is complete. Your login and settings stay.
- **Works on the big distributions.** Ubuntu, Linux Mint, Pop!_OS, Debian (apt), Fedora (dnf),
  Arch, CachyOS, EndeavourOS, Manjaro (pacman).
- **Reproducible.** Proton, the launcher and every helper are pinned versions with checksums, in
  a dedicated folder. Nothing touches your Steam library or other Wine prefixes.
- **Bluetooth that works.** Trainers, power meters, heart-rate straps and controllers pair from
  MyWhoosh's own device screen, through your PC's Bluetooth.
- **Plays nicely with virtual-shifting bridges.** If an app on your PC already owns the trainer
  and offers it as a DirCon (Wahoo Direct Connect) trainer, such as qdomyos-zwift or OsmolControl,
  MyWhoosh can use it over a local bridge instead.
- **Shortcuts where you look for them.** Desktop icons on KDE Plasma, Cinnamon, COSMIC and other
  desktops that show them; the application menu everywhere, including GNOME.

## Requirements

- A 64-bit (x86_64) PC with a GPU that supports Vulkan (any AMD or Intel GPU from the last ~8
  years with Mesa, or NVIDIA with its proprietary driver).
- Bluetooth (built in or a USB dongle), unless you use a DirCon bridge app.
- Free space: about 8 GB for MyWhoosh, about 20 GB for MyWhoosh HD.
- A MyWhoosh account (free).

## Install

Option A, one line (shown above). Option B, look before you run:

```sh
git clone https://github.com/Parapeth962/mywhoosh-linux-installer.git
cd mywhoosh-linux-installer
./install.sh            # asks questions
./install.sh --hd       # MyWhoosh HD, no question about the edition
./install.sh --direct   # Bluetooth straight from MyWhoosh, no question about it
```

What it does, in order:

1. Installs system packages with apt, dnf or pacman: Python 3 with D-Bus bindings, curl, tar,
   BlueZ, notifications, Vulkan drivers (apt/dnf). Turns the Bluetooth service on.
2. Downloads [GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom) 11-9 (SHA-512
   checked) and [umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) 1.4.4.
3. Downloads MyWhoosh from Microsoft's Store servers with
   [ms-store-download](https://github.com/Dj0ulo/ms-store-download) (Microsoft's SHA-256 digests
   checked).
4. Downloads the WinRT/Bluetooth shim from
   [Dj0ulo/mywhoosh-linux](https://github.com/Dj0ulo/mywhoosh-linux) v0.1.3 (checksum pinned).
5. Creates the Proton prefix, disables the bundled Bonjour installer, adds shortcuts, runs a
   self-check.

Everything goes to `~/Games/mywhoosh-linux` (HD: `~/Games/mywhoosh-hd-linux`); Proton goes to
`~/.local/share/Steam/compatibilitytools.d`.

## Ride

1. Switch on your trainer and sensors.
2. Start **MyWhoosh** from the desktop or menu, and log in.
3. **Bluetooth, direct:** Device Connection → **BLE** → pick your trainer, heart-rate strap or
   controller. Keep them disconnected from other apps (a trainer accepts one Bluetooth app).
4. **DirCon bridge:** start your bridge app first, then Device Connection → **BLE** → Power
   Source → the bridged trainer (shown as "DirCon Trainer", or "OsmolControl"). The LAN button
   does not work under Wine; the bridge is the way in.

## Everyday commands

```sh
~/Games/mywhoosh-linux/bin/mywhoosh.sh doctor        # check everything
~/Games/mywhoosh-linux/bin/mywhoosh.sh update        # update now instead of at the next start
~/Games/mywhoosh-linux/bin/mywhoosh.sh reset-prefix  # fresh Windows environment, keeps the game
~/Games/mywhoosh-linux/bin/mywhoosh.sh uninstall     # remove it all
```

`MYWHOOSH_NO_UPDATE=1` skips the update check for one start. Every start leaves a log in
`~/Games/mywhoosh-linux/logs/`; attach the newest one to a bug report.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Nothing opens | Run `doctor`. Read the newest file in `logs/`. If Bonjour is reported, run `reset-prefix`. |
| Trainer not listed under BLE | Is it connected to a phone, Zwift or another app? Disconnect it there. Pedal to wake it up. Check `bluetoothctl show` says `Powered: yes`. |
| Bridged trainer not listed | Start the DirCon app first and make sure it is serving (OsmolControl: press Start ride). The PC needs a network connection, even though everything stays local. |
| Long wait at start | An update is downloading; a notification says so. |
| Low frame rate | Use regular MyWhoosh instead of HD, and lower the graphics preset in MyWhoosh. |

## How it works

```
MyWhoosh (Windows, under Proton)
  └─ .NET Bluetooth code ──► MyWhooshShim.dll (WinRT stand-in, via MONO_PATH)
                                 └─ JSON over 127.0.0.1:27019
                                      ├─ direct:  blehelper.py ──► BlueZ ──► your devices
                                      └─ dircon:  ble-bridge.py ──► DirCon TCP ──► bridge app
```

MyWhoosh's LAN (DirCon) pairing discovers devices through Bonjour COM events, which wine-mono
cannot deliver, so `ble-bridge.py` exposes a DirCon trainer as a Bluetooth device instead and
relays its GATT operations.

## Credits and legal

- The WinRT/Bluetooth shim and its BlueZ helper are by
  [Dj0ulo/mywhoosh-linux](https://github.com/Dj0ulo/mywhoosh-linux); the Store downloader is
  [Dj0ulo/ms-store-download](https://github.com/Dj0ulo/ms-store-download) (MIT). Both are
  downloaded at install time, not redistributed here.
- MyWhoosh is a trademark of its owners. This project is not affiliated with or endorsed by
  MyWhoosh. The game is downloaded from Microsoft's servers, exactly as the Microsoft Store would.
- This repository's scripts are MIT licensed.
