## Welcome 

This documentation guides through the installation of [open TELEMAC-MASCARET](http://www.opentelemac.org/) on a Debian Linux virtual machine. The documentation includes instructions for installing Debian Linux on a virtual machine hosted on Oracle's [VirtualBox](https://www.virtualbox.org/) on Windows 10.

> Note: An internet connecting is required.

## Create Debian Linux Virtual Machine 

Instructions for installing Debian Linux as a virtual machine in Oracle's VirtualBox on Windows 10.

### Get prerequisites

> Estimated duration: 5-10 minutes.

* Download and install the latest version of [VirtualBox](https://www.virtualbox.org/).
* Download the latest Debian Linux net installer:
    + Visit [debian.org](https://www.debian.org/)
    + In the *Getting Debian* section click on *CD/USB ISO images*
    + Click on [Download CD/DVD images using HTTP](https://www.debian.org/CD/http-ftp/)
    + Find the CD-section and click on the [*amd64*](https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/) version
    + Scroll to the bottom of the page and download the latest net installer (*debian-xx.x.x-amd64-netinst.iso*)

Remember where the *.iso* file is stored.
    
### Create Virtual Machine (VM)

> Estimated duration: 5 minutes.

In Windows 10, click on start, type *Oracle VM VirtualBox* and hit enter. In the *VirtualBox* manger window:

* Click on the blue *New* button to open the VM creation wizard and enter:
    + Name: Debian Linux <br>*Note: The wizard should automatically recognize the *Type* and *Version* fields.*
    + Machine Folder: C:\Users\USERNAME\VirtualBox VMs
    + Type: Linux
    + Version: Debian (64-bit)  <br>> Click on the *Next* button
    + Allocate memory size: the more memory is allocated to the VM, the faster will be the VM (and TELEMAC), but the slower will be the main system (Windows 10). Rule of thumb: stay in the green range of the bar (e.g. allocate 8192 MB)
    <br>> Click on the *Next* button
    + Select *Create a virtual hard disk now* and click on the *Create* button.
    + Select *VDI* (native to *VirtualBox*) and click on *Next*.
    + Preferably choose *Dynamically allocated* to start with a small virtual disk size, which can take a maximum size to be defined in the next step. Click on the *Next* button.
    + Leave the default disk name as is and allocate a maximum size for the virtual disk (recommended: min. 32 GB). Click on the *Create* button.  
* Great - the basics are all set now and we are back in the *VirtualBox* main window, where a *Debian Linux* VM should be visible now on the left side of the window.
* With the *Debian Linux* VM highlighted (i.e., just click on it), click on the yellow *Settings* wheel-button, which opens the *Settings* window:
    + In the *System/Motherboard* tab, verify the memory allocation and check the *Enable EFI (special OSes only)* box (enable).
    + In the *System/Processor* tab, select the number of processors that the VM uses. For not slowing down the main system (Windows 10), stay in the green range of the CPU bar. For parallel processing with *TELEMAC*, allocate at least 4 CPUs. 
    + In the *Storage* tab, find the *Controller: IDE*, where an *Empty* disk symbol should be located below. Click on the *Empty* disk symbol and find the *Attributes* frame on the right side of the window, where a small blue disk symbol should be visible. Click on the small blue disk symbol to *Choose a virtual disk file ...*. Select the Debian Linux net installer (*debian-xx.x.x-amd64-netinst.iso*) that we downloaded before.
    + Click *OK*

### Install Debian Linux

> Estimated duration: 30 minutes.

To start the installation of Debian Linux, start the before create Debian Linux VM in the *VirtualBox* manger window (click on the *Debian Linux* VM and then on the green *Start* arrow). The VM Box will ask for the *.iso* file to use (confirm the selected one), and start navigating through the installation:

* Inside the VM Box select the *Graphical install* option.
* Navigate through the language options (recommended: English - English (United States)).
* Optionally define a hostname (e.g. debian-vm) and a domain name (e.g. debian-net).
* Create a root user name and password (note the credentials!) as well as a user name (no root rights) and password.
* Setup the clock.
* Disk partitioning: Choose the *Guided - use entire disk* option. Click *Continue* (2 times).
* Select the *All files in one partition (recommended for new users)* option. Click *Continue*.
* Make sure that *Finish partitioning and write changes to disk* is selected and click *Continue*.
* Select *Yes* in the next step (*Write the changes to disks?*). <br>... grab your favorite beverage and wait while the installation progresses ...
* Select *No* to answer the question *Scan another CD or DVD?* and click *Continue*.
* Select the geographically closest mirror to access Debian archives (software repositories and updates) and click *Continue* (2 times).
* Skip the proxy information question (just click *Continue*).
* Optionally, select *No* to answer the question *Participate in the package usage survey?* and click *Continue*.
* Software to install: Select *GNOME* and keep the other defaults (Debian desktop, print server, and standard system utilities).
 <br>... continue enjoying your favorite beverage and wait while the installation progresses ...
* Click *Continue* to finalize the installation and reboot (or shutdown) the VM.

Once the VM is shut down, re-open the VM *Settings* (from *VirtualBox Manager* window) and go to the *Storage* tab. Verify that there is again an *Empty* disk symbol in the *Controller: IDE* field.

### Setup and Familiarize with Debian Linux

> Estimated duration: 15-20 minutes.

Start the *Debian Linux* VM from the *VirtualBox* manger window. Once Debian Linux has started, log on with your user credentials.

To enable the full functionality of the system, open the Linux Terminal (`CTRL` + `Alt` + `T` or go to *Activities* > *Files* (filing cabinet symbol), right-click in any folder and select *Open in Terminal*). In *Terminal* type:

```
su
```

Enter the above-created password for the root user name (see installation section).

> Note: Root access (e.g. for installing software) is granted on many Linux distribution using the `sudo` command before the command to execute. In Debian Linux, `sudo` may refer to the wrong account and not work as desired. As a workaround use `su` in the *Terminal*.

Install all packages required for building kernel modules:

```
apt update
apt install build-essential dkms linux-headers-$(uname -r)
```

Find the *Devices* drop down menu of the VM Box window (not in Debian Linux itself) and select *Insert Guest Additions CD image ...* (depending on the version of *VirtualBox*, this menu can be on the top or on the bottom of the window).

> The VM Box window does not show the menu with the *Devices* entry anywhere?
    + This may happen when the *View* was set to *Scaled mode*.
    + To toggle the view mode and make the menu bar visible, press the RIGHT `CTRL` (`Host`) key + the `C` on your keyboard, while being in the host system view.

> Note: If an error occurs ("The guest system has no CR-ROM ..."), shutdown the VM. In the *VirtualBox* manager window, right-click on the *Debian Linux* VM > *Storage* tab > Add new Optical Drive to *Controller: IDE*. Restart the *Debian Linux* VM.

Back in the Debian Linux *Terminal* moun the *Guest Additions* *iso* file by typing (do not forget `su` if you needed to restart *Terminal*):

```
mkdir -p /mnt/cdrom
mount /dev/cdrom /mnt/cdrom
```

Navigate to the mounted directory and execute the *VBoxLinuxAdditions.run* file with the *--nox11* flag to avoid spawning an xterm window.

```
cd /mnt/cdrom
sh ./VBoxLinuxAdditions.run --nox11
```

The kernel modules will be installed now and *Terminal* should produce a message that invites to reboot the system. Do so by typing:

```
sudo shutdown -r now
```

After rebooting, make sur that the installation was successful. In *Terminal* type:

```
lsmod | grep vboxguest
``` 

If the *Terminal*'s answer is something like `vboxguest   358395 2 vboxsf`, the installation was successful. 

To improve the visual experience and getting familiar with Debian Linux do the following: 

* In the top-left corner of the Debian Linux Desktop, click on *Activities* and type *display* in the search box. Open the *Displays* settings to select a convenient display resolution. If you selected a too high resolution, the VM Box will turn black and jump back to the original resolution after 15-30 seconds. Consider also to turn on *Night Light* to preserve your eye vision. *Apply* the changes and close the *Displays* settings.
* Familiarize with Debian Linux: Go to the *Activities* menu and find LibreOffice-Writer, Firefox, and the Software application. Find more applications by clicking on the four dots on the left of the menu bar - can you find the Text Editor?
* To shut down the VM, click on the top-right corner arrow and press the Power symbol.

### Enable folder sharing

> Estimated duration: 5 minutes.

Sharing data between the host system (Windows 10) and the guest system (Debian Linux VM) will be needed to transfer input and output files to and from the VM to the physical system.

* At a place of your convenience, create a new folder on the host system (Windows 10) and call it shared (e.g. `C:\Users\USER\documents\shared\`).
* Start *VirtualBox* and the Debian Linux VM.<br>Make sure that the scaled view mode is toggled of (toggle view modes with RIGHT `CTRL` (`Host`) key + the `C` on the keyboard).
* Go to the VM VirtualBox window's *Devices* menu, click on *Shared Folders* > *Shared Folders Settings...* and click on the little blue *Add new shared folder* symbol on the right hand side of the window (see figure below). Make the following settings in the pop-up window:
    + *Folder Path:* Select the just created `...\shared` folder
    + Check the *Enable Auto-mount* box
    + Check the *Make Permanent* box
* Click OK on both pop-up windows.

![share-folder](https://github.com/Ecohydraulics/media/raw/master/png/vm-share-folder.png)

The shared folder will then be visible in the *Files* (*Activities* > *Filing cabinet symbol*) on the left (e.g. as *sf_shared*). A reboot may be required.

> Note: File sharing only works with the *Guest Additions CD image* installed (see above section on setting up and familiarizing with Debian Linux).

## Install TELEMAC Prerequisites


## Download and Compile TELEMAC-MASCARET


## Test TELEMAC MASCARET

