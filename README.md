# Introduction

This repo will help you create an unattended install ISO file with Ubuntu 16 LTS where the default user is "ops" and you choose a password for the user when you build the ISO. 

* SOE = Standard Operating Environment
* We use this image as a bare minimum for what Ansible need to bootstrap our servers
* This Makefile is set up to be run on an Ubuntu Linux system and requires the package "genisoimage" to be installed.
* The username/password is set in my_files/kmg-ks.preseed through replacing the string XXX_PASSWORD_XXX with the content of the file password_hash, which is generated when you run "make soe"
* The resulting ISO image will be named soe-ubuntu-16.04.iso
* The default user is "ops" unless you make the ISO with "make soe USER=XYZ"

The Makefile in this directory will:

* Ask for a password to use for the user "ops"
* The Ubuntu 16.04 LTS image ubuntu-16.04-server-amd64.iso image is automatically downloaded
* A mount point (./mnt) is created
* The Ubuntu ISO image is mounted on ./mnt
* All files in ./mnt is copied to ./work.dir 
* The files in my_files/* are copied to the proper places in ./work.dir
* A new iso image with your configuration is created, which you then can use for an "unattended" installation of Ubuntu 16.04 LTS

```
sudo apt-get -y install genisoimage
make soe
```

Other usage alternatives:

```
make
make clean
make dist-clean
```

Normally you will not need to type "make clean" or "make dist-clean"

## Notes concerning this ISO

* When building this ISO, we default to the old way of network interface naming (eth0, ..., ethN) instead of the new naming scheme by passing arguments to the kernel at boot
* The default user and password is configured in the my_files/kmg-ks.preseed file. See below for how to generate the hashed password if you want to create the file password_hash yourself
* Info: Vagrant uses Virtual box per default, and creates a second NIC interface (eth1 in Ubuntu) with the choosen ip address in the Vagrant file. This way you will have internet access through NAT/DHCP on the primary NIC (eth0), and network access on the local host through the second interface. Therefore the ISO image created here will automatically choose the first available NIC (eth0) as the default network interface.

To ensure that the old network interface naming is used the workaround is to put the following lines into my_files/kmg-ks.preseed to first tell the kernel to use the old eth scheme. This will ensure that the installed VM will use the ethN naming.

* my_files/kmg-ks.preseed -> tells the installer to add an entry in /etc/default/grub (the net...), which will revert to the old ethN scheme

```
#--- re-enabling eth0 interface names for Ubuntu 16 LTS
d-i debian-installer/add-kernel-opts string net.ifnames=0 biosdevname=0
```

You will also have to make sure that the installer use the same naming scheme (ethN). Otherwise the /etc/network/interfaces file will have the wrong interface names after install.

* my_files/isolinux/txt.cfg -> the append of the kernel parameters after -- tells the installer to use the old school ethN scheme

```
default kmg
label kmg
  menu label ^KMG - Install Ubuntu Server
  kernel /install/vmlinuz
  append  file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz ks=cdrom:/kmg-ks.cfg preseed/file=/cdrom/kmg-ks.preseed -- net.ifnames=0 biosdevname=0
```

## References

* http://askubuntu.com/questions/689070/network-interface-name-changes-after-update-to-15-10-udev-changes


# Vagrant -> set up a new vagrant image

This section will describe how you set up a VM in Virtual Box with 2 NICs, an 8GB hard disk, mount the iso image and boot it up for installation.

* Nic1 -> NAT -> Add port forwarding tcp port 9999 to 22, so that you can easily ssh into your system with "ssh -p 9999 ops@localhost" after installation
* Nic2 -> Host only adapter vboxnet0
* Mount soe-ubuntu.iso file of choice
* Boot up the VM for installation

```
#--- choose your own vmName and isoImage location
vmName=test-vl001local
isoImage=/temp/ubuntu/soe-ubuntu-16.04.iso

#--- copy/paste this
VBoxManage createvm --name "$vmName" --register
vmDir=$(VBoxManage showvminfo "$vmName" | grep "^Config file:"  | awk -F":" '{print $2}' | xargs -L1 -IX dirname "X")
VBoxManage modifyvm "$vmName" --memory 512 --acpi on --boot1 dvd --vram 33 --cpus 1
VBoxManage modifyvm "$vmName" --nic1 nat --nictype1 82540EM
VBoxManage modifyvm "$vmName" --nic2 hostonly --nictype2 82540EM --hostonlyadapter2 vboxnet0
VBoxManage modifyvm "$vmName" --natpf1 ",tcp,,9999,,22"
VBoxManage modifyvm "$vmName" --ostype Ubuntu_64
VBoxManage createhd --filename "$vmDir/${vmName}.vdi" --size 8000
VBoxManage storagectl "$vmName" --name "SATA" --add sata
VBoxManage storageattach "$vmName" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "${vmDir}/${vmName}.vdi"
VBoxManage storagectl "$vmName" --name "IDE" --add ide
VBoxManage storageattach "$vmName" --storagectl "IDE" --port 1 --device 0 --type dvddrive --medium "$isoImage"

VBoxManage showvminfo "$vmName"
VBoxManage startvm "$vmName"
#VBoxManage unregistervm "$vmName" --delete
```

* Boot and install (automatic install)

The installation will take a couple of minutes.

* Attach VBoxGuesAdditions

```
#--- linux:
additionsIso=/usr/share/virtualbox/VBoxGuestAdditions.iso

#--- mac: 
additionsIso=/Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso

VBoxManage storageattach "$vmName" --storagectl "IDE"  --port 1 --device 0 --type dvddrive --medium "${additionsIso}"
```

* Connect to your newly installed VM with the user you have as default user in your iso image. The port 9999 is choosen above when we created the virtual machine, and we are ignoring the fact that your known_hosts file might be tainted by old incarnations of this ip address:

```
ssh -p 9999 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ops@localhost
```

* Run the following commands in the newly installed VM

```
echo "vagrant ALL=(ALL) NOPASSWD:ALL" | sudo tee  /tmp/vagrant.sudoers
sudo visudo -f /tmp/vagrant.sudoers -c && sudo chmod 600 /tmp/vagrant.sudoers && sudo mv /tmp/vagrant.sudoers /etc/sudoers.d/vagrant
sudo useradd -m -s /bin/bash vagrant
echo -e "vagrant\nvagrant" | sudo passwd vagrant

sudo -u vagrant mkdir -p /home/vagrant/.ssh
sudo chmod 0700 /home/vagrant/.ssh
sudo -u vagrant wget --no-check-certificate  https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub  -O /home/vagrant/.ssh/authorized_keys
sudo chmod 0600 /home/vagrant/.ssh/authorized_keys
sudo chown -R vagrant /home/vagrant/.ssh

cat<<EOT | sudo tee -a /etc/network/interfaces
#VAGRANT-BEGIN
# The contents below are automatically generated by Vagrant. Do not modify.
auto eth1
iface eth1 inet static
      address 1.2.3.4
      netmask 255.255.255.0
#VAGRANT-END
EOT
```

* If you did not already mount the VBoxGuestAdditions.iso (see above), select the console window for your VM and select Devices->Insert Guest Additions CD. Then do the following to mount the DVD and install the guest additions:

```
sudo apt-get install -y gcc build-essential

sudo mount /dev/cdrom /mnt
cd /mnt
sudo ./VBoxLinuxAdditions.run
```

* On your local computer (based on the assumption that your Virtualbox VM is named test-vl001local):

```
cd
boxName=soe-linux
vmName=test-vl001local
mkdir vagrant_packages
cd vagrant_packages
[ -f package.box ] && rm package.box
vagrant package --base test-vl001local
vagrant box add $boxName package.box --force
```

## References

* https://blog.engineyard.com/2014/building-a-vagrant-box
* https://www.virtualbox.org/manual/ch08.html
* http://nakkaya.com/2012/08/30/create-manage-virtualBox-vms-from-the-command-line/

# Extras

## Remove MBR

```
# sudo dd if=/dev/zero of=/dev/sda bs=446 count=1
```

## Generate password on the commandline

```
mkpasswd  -m sha-512 -S saltsalt -s <<< mySuperSecretPassword
```

# References

* https://help.ubuntu.com/community/Cobbler/Preseed
* https://help.ubuntu.com/lts/installation-guide/example-preseed.txt
* https://www.digitalocean.com/community/tutorials/what-s-new-in-ubuntu-16-04

* https://robots.thoughtbot.com/the-magic-behind-configure-make-make-install
