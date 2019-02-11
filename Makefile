#=======================================================
# Makefile for soe-ubuntu
#
# Description: This makefile works on Linux and MacOS
#
# Dependencies:
#   - MacOS: brew, brew packages: dvdrtools
#
#=======================================================

MY_FILES = my_files

RELEASE=18

ifeq ($(RELEASE),16)
	BASE_VERSION = 16.04
	VERSION = 16.04.5
else
	BASE_VERSION = 18.04
	VERSION = 18.04.1
endif

DST_IMAGE = soe-ubuntu-$(VERSION).iso
BASE_IMAGE = ubuntu-$(VERSION)-server-amd64.iso

#--- 16.04.1 use the following URL
ifeq ($(BASE_VERSION),16.04)
	BASE_URL = http://mirror.init7.net/ubuntu-releases/$(BASE_VERSION)
else
#--- 18.04.1 use the following URL
#--- The Ubuntu 18 should be installed with the alternate installer
	BASE_URL=http://cdimage.ubuntu.com/releases/$(BASE_VERSION)/release
endif

WORK_DIR = work.dir

USER = ops
#PASSWORD = P@ssw0rd
SALT = saltsalt


TIMEZONE = Europe/Zurich

PROXY_URL = 10.0.20.5
PROXY_PORT = 3142

MNT_DIR = mnt

OS := $(shell uname)

CUR_USER := $(shell id -u)
CUR_GROUP := $(shell id -g)

#ASK_PASSWORD ?= $(shell stty -echo; read -p "$(USER) Password: " pwd; stty echo; echo $$pwd)
#PASSWORD := $(ASK_PASSWORD)


help:
	@echo "Usage:"
	@echo ""
	@echo "make clean       # will unmount the source image and remove mnt and remove the password_hash file"
	@echo "make dist-clean  # will make clean and remove the $(WORK_DIR) directory"

	@echo ""
	@echo "#--- some helpful stuff"
	@echo "make download    # will download the ubuntu iso"
	@echo "make mnt         # will download the ubuntu iso and mount it on ./mnt"
	@echo ""
	@echo "#--- Variables - as set right now"
	@echo ""
	@echo "RELEASE      = $(RELEASE)"
	@echo "BASE_VERSION = $(BASE_VERSION)"
	@echo "VERSION      = $(VERSION)"
	@echo "ISO          = $(BASE_URL)/$(BASE_IMAGE)"

	@echo ""
	@echo "#--- the magic"
	@echo "make soe RELEASE=16   # will copy the files in my_files and create the image for Ubuntu 16"
	@echo "make soe              # will copy the files in my_files and create the image for Ubuntu 18"
	@echo "make soe USER=$(USER) # will copy the files in my_files and create the image using $(USER) as credentials for the default user"

password_hash:
ifeq ($(OS),Darwin)
	$(eval PASSWORD := $(shell stty -echo; read -p "$(USER) Password: " pwd; stty echo; echo $$pwd))
	openssl passwd -1 -salt "$(SALT)" "$(PASSWORD)" > password_hash
else
	mkpasswd  -m sha-512 -S $(SALT)  > password_hash
endif

all: soe

mount: $(BASE_IMAGE) $(MNT_DIR) $(MNT_DIR)/md5sum.txt

download: $(BASE_IMAGE)

umount:
	sudo umount $(MNT_DIR)

work: $(WORK_DIR)/md5sum.txt

soe: password_hash $(MNT_DIR)/md5sum.txt $(WORK_DIR)
	cat $(MY_FILES)/$(BASE_VERSION)/kmg-ks.preseed | sed -e "s/XXX_USER_XXX/$(USER)/g" -e "s,XXX_PASSWORD_XXX,`cat password_hash`,g" -e "s/XXX_PUBLIC_KEY_XXX/`cat public_key`/g" -e "s,XXX_TIMEZONE_XXX,$(TIMEZONE),g" | sudo tee $(WORK_DIR)/kmg-ks.preseed
	sudo cp $(MY_FILES)/$(BASE_VERSION)/show-ip-address $(WORK_DIR)/show-ip-address

#--- only for proxy based installations
#	cat $(MY_FILES)/proxy.template | sed -e "s/XXX_PROXY_URL_XXX/$(PROXY_URL)/g" -e "s/XXX_PROXY_PORT_XXX/$(PROXY_PORT)/g" | sudo tee -a $(WORK_DIR)/kmg-ks.preseed

	sudo cp $(MY_FILES)/isolinux/lang $(WORK_DIR)/isolinux
	cat $(MY_FILES)/isolinux/txt.cfg | sed -e "s!XXX_PRESEED_CHECKSUM_XXX!`md5 -r $(WORK_DIR)/kmg-ks.preseed | cut -d" " -f 1`!" | sudo tee $(WORK_DIR)/isolinux/txt.cfg
	cat $(MY_FILES)/$(BASE_VERSION)/grub.cfg | sed -e "s!XXX_PRESEED_CHECKSUM_XXX!`md5 -r $(WORK_DIR)/kmg-ks.preseed | cut -d" " -f 1`!" | sudo tee $(WORK_DIR)/boot/grub/grub.cfg

	cat $(WORK_DIR)/isolinux/txt.cfg
	cat $(WORK_DIR)/boot/grub/grub.cfg


ifeq ($(OS),Darwin)
	sudo mkisofs -D -r -V "Attendless_Ubuntu" -J -l -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -z -iso-level 3 -c isolinux/isolinux.cat -o ./$(DST_IMAGE) $(WORK_DIR)
	sudo chown $(CUR_USER):$(CUR_GROUP) $(DST_IMAGE)
	./isohybrid.pl $(DST_IMAGE)
else
	sudo mkisofs -U -A "Custom1804" -V "Custom1804" -volset "Custom1804" -J -joliet-long -r -v -T -o ./$(DST_IMAGE) -b isolinux/isolinux.bin -c isolinux/isolinux.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot $(WORK_DIR)
	sudo chown $(CUR_USER):$(CUR_GROUP) $(DST_IMAGE)
	isohybrid --uefi $(DST_IMAGE)
endif

	sudo umount $(MNT_DIR)

#=====================================================
# Atomic rules
#=====================================================
$(MNT_DIR): $(BASE_IMAGE) 
	[ -d $@ ] || mkdir $@ 

$(MNT_DIR)/md5sum.txt: $(MNT_DIR)
ifeq ($(OS),Darwin)
	#--- this is a sequence where the semicolon and backslash is extremely important
	set -e ;\
	ISO_DEVICE=$$(hdiutil attach -nobrowse -nomount ./$(BASE_IMAGE) | head -1 | cut -d" " -f1) ;\
	echo "iso $$ISO_DEVICE" ;\
	mount -t cd9660 $$ISO_DEVICE $(MNT_DIR)

else
	sudo mount -o loop $(BASE_IMAGE) $(MNT_DIR)
endif

$(WORK_DIR)/md5sum.txt: $(MNT_DIR)
	[ -d $(WORK_DIR) ] || mkdir $(WORK_DIR) || true
	(cd mnt; sudo tar cf - .) | (cd $(WORK_DIR); pwd ; sudo tar xf - )

$(WORK_DIR): $(WORK_DIR)/md5sum.txt 

$(BASE_IMAGE):
	wget "$(BASE_URL)/$(BASE_IMAGE)"

clean:
	[ -d $(WORK_DIR) ] && sudo rm -rf $(WORK_DIR) || true
	[ -d mnt ] && sudo umount mnt || true
	[ -d mnt ] && rmdir mnt || true
	[ -f password_hash ] && rm password_hash || true

dist-clean: clean
	[ -f $(DST_IMAGE) ] && sudo rm $(DST_IMAGE) || true

