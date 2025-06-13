# Killswitch Project

## Overview

**Killswitch** is a Linux utility that enforces a VPN killswitch using UFW (Uncomplicated Firewall). It ensures all internet traffic is blocked unless your VPN connection is active, protecting your privacy and preventing accidental data leaks.

## Features

- Automatically configures UFW rules for VPN interfaces (OpenVPN and WireGuard)
- Adds sudoers rules for seamless script execution without password prompts
- Simple setup script for user convenience
- Supports `.ovpn` configuration files

## Installation

1. **Build or Download the `.deb` package:**
   - If you have the source, build the package:
     ```sh
     dpkg-deb --build killswitch
     ```
   - Or download the prebuilt `killswitch.deb`.

3. **Install the package:**
   ```sh
   sudo dpkg -i killswitch.deb
   ```

## Usage

1. **Run the setup script:**
   ```sh
   sudo /usr/local/bin/skript.sh
   ```
   - You will be prompted to enter the full path to your `.ovpn` file.

2. **Enable the killswitch:**
   ```sh
   sudo /usr/local/bin/killswitch-on.sh
   ```

3. **Disable the killswitch:**
   ```sh
   sudo /usr/local/bin/killswitch-off.sh
   ```

## How It Works

- The setup script configures UFW to only allow internet traffic through the VPN tunnel (`tun0` or `wg0`).
- It blocks all other outgoing traffic, ensuring no data leaks if the VPN disconnects.
- Sudoers rules are added so you can toggle the killswitch scripts without entering your password.

## Troubleshooting

- **VPN not connecting?**  
  Double-check your `.ovpn` file path and VPN credentials.
- **No internet after disconnecting VPN?**  
  Run `killswitch-off.sh` to restore normal connectivity.
- **Permission errors?**  
  Ensure you run scripts with `sudo`.

## Uninstallation

```sh
sudo dpkg -r myshortcut
```

## License

MIT License

---

**Contributions and issues