MY_FILES = my_files
DST_IMAGE = soe-ubuntu-16.04.iso
BASE_IMAGE = ubuntu-16.04-server-amd64.iso
WORK_DIR = work.dir

USER = ops
PASSWORD = password
SALT = saltsalt

MNT_DIR = mnt

help:
	@echo "Usage:"
	@echo ""
	@echo "make clean       # will unmount the source image and remove mnt"
	@echo "make dist-clean  # will make clean and remove the $(WORK_DIR) directory"

	@echo ""
	@echo "#--- some helpful stuff"
	@echo "make mnt         # will download the ubuntu iso and mount it on ./mnt"

	@echo ""
	@echo "#--- the magic"
	@echo "make soe                             # will copy the files in my_files and create the image"
	@echo "make soe USER=$(USER) PASSWORD=$(PASSWORD)  # will copy the files in my_files and create the image using $(USER) as credentials for the default user"

	@echo "Debug: $(ASD)"


.password_hash:
	mkpasswd  -m sha-512 -S $(SALT)  > .password_hash

all: soe

mount: $(MNT_DIR) $(MNT_DIR)/md5sum.txt

work: $(WORK_DIR)/md5sum.txt

soe: $(WORK_DIR) .password_hash
	@echo "Password: $(PASSWORD)"
	cat $(MY_FILES)/kmg-ks.cfg | sudo tee $(WORK_DIR)/kmg-ks.cfg 
	cat $(MY_FILES)/kmg-ks.preseed | sed -e "s/XXX_USER_XXX/$(USER)/g" -e "s!XXX_PASSWORD_XXX!`cat .password_hash`!g" | sudo tee $(WORK_DIR)/kmg-ks.preseed
	sudo cp $(MY_FILES)/isolinux/lang $(WORK_DIR)/isolinux
	sudo cp $(MY_FILES)/isolinux/txt.cfg $(WORK_DIR)/isolinux
	sudo mkisofs -D -r -V "Attendless_Ubuntu" -J -l -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -z -iso-level 4 -c isolinux/isolinux.cat -o ./$(DST_IMAGE) $(WORK_DIR)

#=====================================================
# Atomic rules
#=====================================================
$(MNT_DIR): $(BASE_IMAGE) 
	[ -d $@ ] || mkdir $@ 

$(MNT_DIR)/md5sum.txt:
	sudo mount -o loop $(BASE_IMAGE) mnt

$(WORK_DIR)/md5sum.txt: $(MNT_DIR)
	[ -d $(WORK_DIR) ] || mkdir $(WORK_DIR) || true
	(cd mnt; sudo tar cf - .) | (cd $(WORK_DIR); pwd ; sudo tar xf - )

$(WORK_DIR): $(WORK_DIR)/md5sum.txt 

$(BASE_IMAGE):
	wget "http://mirror.switch.ch/ftp/mirror/ubuntu-cdimage/16.04/$(BASE_IMAGE)"

clean:
	[ -d mnt ] && sudo umount mnt || true
	[ -d mnt ] && rmdir mnt || true
	[ -f .password_hash ] && rm .password_hash || true

dist-clean: clean
	[ -d $(WORK_DIR) ] && sudo rm -rf $(WORK_DIR) || true
	[ -f $(DST_IMAGE) ] && sudo rm $(DST_IMAGE) || true

