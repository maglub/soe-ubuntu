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
#BASE_VERSION = 16.04
BASE_VERSION = 18.04
#BASE_VERSION = artful
#VERSION = 16.04.5
#VERSION = 17.10.1
#VERSION = 18.04.1-live
VERSION = 18.04.1

DST_IMAGE = soe-ubuntu-$(VERSION).iso
BASE_IMAGE = ubuntu-$(VERSION)-server-amd64.iso

#--- 16.04.1 use the following URL
BASE_URL = http://mirror.switch.ch/ftp/mirror/ubuntu-cdimage/$(BASE_VERSION)

#--- 18.04.1 use the following URL
#BASE_URL = http://cdimage.ubuntu.com/releases/$(VERSION)/release

WORK_DIR = work.dir

USER = ops
PASSWORD = password
SALT = saltsalt

TIMEZONE = Europe/Zurich

PROXY_URL = 10.0.20.5
PROXY_PORT = 3142

MNT_DIR = mnt

OS := $(shell uname)

CUR_USER := $(shell id -u)
CUR_GROUP := $(shell id -g)


help:
	@echo "Usage:"
	@echo ""
	@echo "make clean       # will unmount the source image and remove mnt and remove the password_hash file"
	@echo "make dist-clean  # will make clean and remove the $(WORK_DIR) directory"

	@echo ""
	@echo "#--- some helpful stuff"
	@echo "make mnt         # will download the ubuntu iso and mount it on ./mnt"

	@echo ""
	@echo "#--- the magic"
	@echo "make soe              # will copy the files in my_files and create the image"
	@echo "make soe USER=$(USER) # will copy the files in my_files and create the image using $(USER) as credentials for the default user"

	@echo "Debug: $(ASD)"


password_hash:
ifeq ($(OS),Darwin)
	openssl passwd -1 "P@ssw0rd" > password_hash
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
	@echo "Password: $(PASSWORD)"
	#cat $(MY_FILES)/$(BASE_VERSION)/kmg-ks.cfg | sudo tee $(WORK_DIR)/kmg-ks.cfg 
	cat $(MY_FILES)/$(BASE_VERSION)/kmg-ks.preseed | sed -e "s/XXX_USER_XXX/$(USER)/g" -e "s/XXX_PASSWORD_XXX/`cat password_hash`/g" -e "s/XXX_PUBLIC_KEY_XXX/`cat public_key`/g" -e "s,XXX_TIMEZONE_XXX,$(TIMEZONE),g" | sudo tee $(WORK_DIR)/kmg-ks.preseed
	sudo cp $(MY_FILES)/$(BASE_VERSION)/show-ip-address $(WORK_DIR)/show-ip-address
#	cat $(MY_FILES)/proxy.template | sed -e "s/XXX_PROXY_URL_XXX/$(PROXY_URL)/g" -e "s/XXX_PROXY_PORT_XXX/$(PROXY_PORT)/g" | sudo tee -a $(WORK_DIR)/kmg-ks.preseed
	sudo cp $(MY_FILES)/isolinux/lang $(WORK_DIR)/isolinux
	cat $(MY_FILES)/isolinux/txt.cfg | sed -e "s!XXX_PRESEED_CHECKSUM_XXX!`md5 -r $(WORK_DIR)/kmg-ks.preseed | cut -d" " -f 1`!" | sudo tee $(WORK_DIR)/isolinux/txt.cfg
	cat $(WORK_DIR)/isolinux/txt.cfg
	sudo mkisofs -D -r -V "Attendless_Ubuntu" -J -l -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -z -iso-level 3 -c isolinux/isolinux.cat -o ./$(DST_IMAGE) $(WORK_DIR)
	sudo mkisofs -U -A "Custom1804" -V "Custom1804" -volset "Custom1804" -J -joliet-long -r -v -T -o ./dual.$(DST_IMAGE) -b isolinux/isolinux.bin -c isolinux/isolinux.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot $(WORK_DIR)


	sudo chown $(CUR_USER):$(CUR_GROUP) $(DST_IMAGE)
	sudo umount $(MNT_DIR)
ifeq ($(OS),Darwin)
	./isohybrid.pl $(DST_IMAGE)
else
	isohybrid $(DST_IMAGE)
endif

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
#	wget "http://mirror.switch.ch/ftp/mirror/ubuntu-cdimage/$(BASE_VERSION)/$(BASE_IMAGE)"
	wget "$(BASE_URL)/$(BASE_IMAGE)"

clean:
	[ -d mnt ] && sudo umount mnt || true
	[ -d mnt ] && rmdir mnt || true
	[ -f password_hash ] && rm password_hash || true

dist-clean: clean
	[ -d $(WORK_DIR) ] && sudo rm -rf $(WORK_DIR) || true
	[ -f $(DST_IMAGE) ] && sudo rm $(DST_IMAGE) || true

