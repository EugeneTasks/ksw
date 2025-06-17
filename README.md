# Killswitch Project

## Overview

Killswitch is a Linux utility that enforces a VPN killswitch using UFW (Uncomplicated Firewall). It ensures all internet traffic is blocked unless your VPN connection is active, protecting your privacy and preventing accidental data leaks.

## Features

- Automatically configures UFW rules for VPN interfaces (OpenVPN and WireGuard).
- Adds sudoers rules for seamless script execution without password prompts.
- Adds services for start killswitch after boot.

## Installation Options

You can install Killswitch in two ways: manual setup or via a `.deb` package.

### WARNING

During instalation process you need to provide script with absolute path of .ovpn config file.

### 1. Manual Setup from the Repository

If you have cloned or downloaded the killswitch repository:

1. Make the setup script executable:
    ```sh
    chmod +x ./usr/local/bin/setup.sh
    ```

2. Run the setup script:
    ```sh
    sudo ./usr/local/bin/setup.sh
    ```
    This will guide you through the setup process, where you'll be prompted to specify the path to your `.ovpn` file.

### 2. Build or Install the .deb Package

- **Build the package:**

    From inside the killswitch repository folder:
    ```sh
    dpkg-deb --build killswitch
    ```
    This will create the `killswitch.deb` file in the current directory.

- **Install the package:**
    ```sh
    sudo dpkg -i killswitch.deb
    ```

## Usage

- **Run the setup script:**

    Whether you installed via `.deb` or manually:
    ```sh
    sudo /usr/local/bin/setup.sh
    ```
    During the setup, you'll be prompted to enter the full path to your `.ovpn` file.

- **Enable the killswitch:**
    ```sh
    sudo /usr/local/bin/killswitch-on.sh
    ```

- **Disable the killswitch:**
    ```sh
    sudo /usr/local/bin/killswitch-off.sh
    ```

## How It Works

- **Setup:** The setup script configures UFW to only allow internet traffic through the VPN tunnel (`tun0` or `wg0`).
- **Block Traffic:** All other outgoing traffic is blocked, ensuring no data leaks if the VPN disconnects.
- **Simplicity:** Sudoers rules are added so you can toggle the killswitch scripts without entering your password.
- **Automation:** Creates killswitch.service and killswitch-notify.service that manage start killswitch and notify user about it after boot.

## Troubleshooting

- **VPN not connecting?**  
  Double-check the path to your `.ovpn` file and verify your VPN credentials.

- **No internet after VPN disconnects?**  
  Disable the killswitch to restore normal connectivity:
    ```sh
    sudo /usr/local/bin/killswitch-off.sh
    ```

- **Permission errors?**  
  Ensure you're running the scripts with `sudo`.

## Uninstallation

To remove the package:
```sh
sudo dpkg -r SAFEKillswitch
```

## License

MIT License

---
This version includes clear instructions for both manual and `.deb` installation methods, ensuring setup is straightforward for all users.