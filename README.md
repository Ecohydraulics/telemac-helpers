# Numerical Software Installers

This repository provides auto-installer scripts and helper files for open-source numerical modelling software (TELEMAC-MASCARET, REEF3D, Delft3D) on Debian-family Linux systems, as described on [hydro-informatics.com](https://hydro-informatics.com/get-started/install-telemac.html).

## Contents

### `debian12/`

TELEMAC-MASCARET (+ optional SALOME) installer for Debian 12:

- `telemac_debian12_installer.sh` - installs TELEMAC and its dependencies, and optionally SALOME with MED libraries wired into TELEMAC.
- `pysource.debian12.sh` - Python source (environment activation) file for the compiled TELEMAC installation.
- `systel.debian12.cfg` - TELEMAC build configuration file for Debian 12.

### `ubuntu24-mint22/`

TELEMAC-MASCARET (+ optional SALOME) installer for Ubuntu 24.04 (noble) and Linux Mint 22:

- `telemac_ubuntu24_installer.sh` - installs TELEMAC and its dependencies, and optionally SALOME.
- `pysource.mint22.sh` - Python source (environment activation) file for the compiled TELEMAC installation.
- `systel.mint22.cfg` - TELEMAC build configuration file for Ubuntu 24.04 / Linux Mint 22.

### `delft3d-installer/`

- `install-delft3d-flow-native.sh` - native (non-Docker) build attempt for Delft3D-FLOW / the Delft3D 4 suite on Ubuntu or Linux Mint. Deltares officially supports Linux builds through an AlmaLinux/oneAPI container; this script tries to reproduce enough of that environment on an apt-based host. Supports options such as `--config flow2d3d`, `--tag`, `--prefix`, `--skip-oneapi-install`, and `--no-apt`.

### `reef3d-installer/`

- `install_reef3d.sh` - auto-installer for REEF3D and DIVEMesh on Debian-family Linux systems.

### `model-templates/`

Template files for setting up a Telemac3D simulation:

- `t3d_template.cas` - commented Telemac3D steering (case) file template.
- `flume3d_bc.bnd` - boundary condition file for a flume/canal example.
- `t3d_canal.qsl` - stage-discharge (QSL) file defining liquid boundary inflows/outflows.

### `linux-tools/`

- `rename_folders.sh` - recursively replaces spaces with dashes in file and folder names below a user-provided directory (useful because TELEMAC and many scientific tools choke on paths containing spaces).

## Usage

Make an installer executable and run it, for example:

```bash
chmod +x telemac_debian12_installer.sh
./telemac_debian12_installer.sh
```

## Warning

These installer scripts are provided for informational and convenience purposes only. They may install packages, download third-party software, compile source code, create files or symbolic links, and modify user-level configuration or desktop/menu entries. Review each script before running it. Use at your own risk.

See [LICENSE](./LICENSE) and [DISCLAIMER.md](./DISCLAIMER.md).
