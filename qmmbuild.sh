 # you can past this function in a shell directly
 # deja espacio antes de la funcion para ke no se guarda esta gran funcion en el history file
 # deja datenowForHostname fuera de la function qemu_create_vm para ke se crean las variable de abajo despues de esta funcion
 export datenowForHostname=$(date +%Y%m%d%H%M%S)

  
 qemu_create_vm(){
 
# si ejecuto esta function desde un interactive bash shell y hago ctrl-c me cerrara el ssh session tb a causa de trap ke se ejecutara dentro del shell
# solution: ejecuta todo en un subshell () 
# https://stackoverflow.com/questions/47380808/bash-exiting-current-function-by-calling-another-function
(
########################################################
# variables
########################################################
# I need to create the repository manually
# repository=/media/hd2/_MyQemuStore_TESTING_deleteme
repository=/media/ssd2/_MyQemuStore 

ROOTPASSWD=bbbbbbnn

IMGSIZE=8G
# qcow2 is as fast as raw in my tests, so let s use it because of snapshots in qcow2
# ImgFormat=raw
ImgFormat=qcow2

# ETH_DEVICE=ens3
ETH_DEVICE=eth0

########################################################

ARCH=amd64
# DISKNAME=sda   # usalo con -device ide-hd o -device scsi-hd o -device virtio-scsi-pci o -hda
DISKNAME=vda   # usalo con virtio -device virtio-blk-pci


# sin haveged aprece un error :random: 7 urandom warning(s) missed due to ratelimiting
common_packages="haveged,dbus,apt-transport-https,wget,curl,locales,tzdata,man-db,manpages,dialog,procps,sudo,net-tools,nano,ifupdown,iproute2,apt-utils,less,lnav,ca-certificates,bash-completion,fzf,qemu-guest-agent"

# ca-certificates solve this error: ERROR: The certificate of ‘github.com’ doesn't have a known issuer.
# https://stackoverflow.com/questions/9224298/how-do-i-fix-certificate-errors-when-running-wget-on-an-https-url-in-cygwin

# bash-completion
# tab in qemu in debian do not work,  i cannot complet apt in... with tab
# https://unix.stackexchange.com/questions/312456/debian-apt-not-apt-get-autocompletion-not-working

# ifupdown
# ubuntu 18 instala netplan pero si instalo ifupdown se usara ifupdown al configurar /etc/network/interfaces


########################################################
# sometimes I will want to install the vm in another disk so:
# I will create a config file where I will save the repositories I use so i can control them all with qmm
grep -F "${repository}" /etc/_qmm.conf || { echo "${repository}" >> /etc/_qmm.conf ; }


########################################################
# common
########################################################
_common_functions(){
    # export datenowForHostname=$(date +%Y%m%d%H%M%S)
    echocolors(){
        INFOC()   { echo -e "\e[0;30m\e[42m" ; }      # black on green 
        WARNC()   { echo -e "\e[0;1;33;40;7m" ; }     # black on yellow ;usa invert 7; y light text 1 
        ERRORC()  { echo -e "\e[0;1;37m\e[41m" ; }    # bright white on red

        HIDEC()   { echo -e "\e[0;1;30m\e[47m" ; }    # hide color: white on grey (bright)
        #HIDEC()   { echo -e "\e[0;1;7;30m\e[47m" ; } # hide color: white on grey (darker)
        ENDC()    { echo -e "\e[0m" ; }               # reset colors

        INFO2C()  { echo -e "\e[0;1;37m\e[44m" ; }    # bright white on blue; 1  is needed sino 37 vuelve grey in mintty
        INFO3C()  { echo -e "\e[0;30m\e[46m" ; }      # black on white blue
    }
    export -f echocolors
    echocolors

    ###################################################
    #sal si pasa un error y guardalo in el log general
    ###################################################

    #(unofficial strict mode)
    set -euo pipefail 

    #TODO : ke hace esto?
    set -E   #set -o errtrace


    error_handler() {  # TODO investiga porke ${BASH_SOURCE[*]} imprime el source  dos veces
        ERRORC
        echo ''
        echo '_________________________________'
        echo "${datenowForHostname}___error non-zero con exit code $?"
        echo ''
        echo "___en la linea ${BASH_LINENO[*]} in ${BASH_SOURCE[*]}"
        echo ''
        echo "___last bash command: $BASH_COMMAND"
        echo '_________________________________'
        echo ''
        ENDC
        # read -p 'Press enter to exit'
        # disable trap and fail on errors sino me saldra el bash on errors
        # set +euo pipefail 
        # set +E
        # trap - ERR EXIT RETURN INT
        
        # echo "error happened so let s remove the image: ${VMfile}"
        # test -f ${VMfile} && rm ${VMfile}
        
        exit 1
    }

    trap "error_handler" ERR
    export -f "error_handler"
    
}
_common_functions
export -f _common_functions

########################################################
# main
########################################################

UmountIfMounted() { findmnt -rno SOURCE,TARGET "$1" >/dev/null && { umount "$1" && echo "$1 fue unmounted..." || return 100 ; } || true ; } #$1:path or device

umount_all(){
    echo _umount all
    [ "${MNT_DIR:-}" = "" ] || {
        UmountIfMounted $MNT_DIR/proc 
        UmountIfMounted $MNT_DIR/sys 
        UmountIfMounted $MNT_DIR/dev/pts 
        UmountIfMounted $MNT_DIR/dev 
        UmountIfMounted $MNT_DIR/boot
        sleep 1s
        UmountIfMounted $MNT_DIR
        sleep 1s
    }
    
    echo _disconnect nbd
    # si pasa un error y no kiere diconectar entonces haz 
    # for i in {0..18} ; do qemu-nbd --disconnect /dev/nbd$i ; done
    [ "${DISK:-}" = "" ] || { qemu-nbd --disconnect $DISK || true ; }
    sleep 1s
    rmmod nbd || true
}

_clean() {
    WARNC ; echo "begin cleaning..." ; ENDC
    umount_all
    
    test -d $MNT_DIR && rm -r $MNT_DIR || true
    
    # si qemu_image_finished no es igual finished  borramos la imagen 
    [ "${qemu_image_finished:-}" = "NOTfinished" ] && { 
        echo "qemu image not finished so let s remove the image: ${VMfile}"
        # test -f ${repository}/${VMfile} && rm ${repository}/${VMfile}
        test -d ${repository}/${VMname} && rm -rf ${repository}/${VMname}
    }
    
    # disable trap and fail on errors sino me saldra el bash on errors
    # set +euo pipefail 
    # set +E
    # trap - ERR EXIT RETURN INT
    
    # esta linea es importante sino se ejecuta el trap ERR si la linea de arriba da exit 1
    echo "end cleaning..."
    exit 1
}



if [ $# -lt 4 ]
then
    WARNC ; echo "usage: $0 <image-file> <hostname> <OS name> <OSversion> [optional debootstrap args]
qemu_create_vm   buster${datenowForHostname}     buster${datenowForHostname}     debian   buster
qemu_create_vm   testing${datenowForHostname}    testing${datenowForHostname}    debian   bullseye
qemu_create_vm   testing${datenowForHostname}    testing${datenowForHostname}    debian   testing
qemu_create_vm   unstable${datenowForHostname}   unstable${datenowForHostname}   debian   unstable

qemu_create_vm   xenial${datenowForHostname}     xenial${datenowForHostname}     ubuntu   xenial
qemu_create_vm   bionic${datenowForHostname}     bionic${datenowForHostname}     ubuntu   bionic
qemu_create_vm   focal${datenowForHostname}      focal${datenowForHostname}      ubuntu   focal
    " 1>&2 ; ENDC
    # exit 1
fi

VMname=$1
HOSTNAME=$2
OSFLAVOUR=$3
OSversion=$4
shift 4


# this will run always, EXIT es para cuando este script como script file, y RETURN es para cuando ejecuto la function directamente desde un shell
trap _clean EXIT RETURN INT



qemu_image_finished=NOTfinished


VMfile=${VMname}.${ImgFormat}
test -d "${repository}" || { ERRORC ; echo "repository of qemu images was not created. create one manually first. you told me to use : ${repository}" ; ENDC ; false ; }
cd "${repository}"
mkdir ${VMname}
cd ${VMname}

apt-get --no-install-recommends install qemu-system-x86 qemu-utils parted debootstrap

test -f ${VMfile} && { WARNC ; echo "image file exist: ${VMfile}" ; ENDC ; false ; }

INFOC ; echo "Installing $OSversion into ${VMfile}..." ; ENDC

MNT_DIR=`tempfile`
rm $MNT_DIR
mkdir $MNT_DIR
DISK=

INFO3C ; echo "temp dir es: $MNT_DIR" ; ENDC

########################################################
# creat image
########################################################
INFOC ; echo "Creating ${VMfile}" ; ENDC
# qemu-img create -f ${ImgFormat} ${VMfile} $IMGSIZE
if [ ${ImgFormat} == qcow2 ]; then
    # for OS disk use a qcow if i need snapshots , otherwise use raw image if i do not need snapshots
    # for other data disks which are not OS use raw because i do not need snashots for them
    # For best performance using a qcow2 image file, increase the cluster size when creating the qcow2 file,use prealocating sobre todo si uso aio=native
    qemu-img create -f qcow2 -o preallocation=full -o cluster_size=2M ${VMfile} $IMGSIZE
elif [ ${ImgFormat} == raw ]; then
    # For best performance using a raw image file, preallocate the disk space:
    qemu-img create -f raw -o preallocation=full ${VMfile} $IMGSIZE
fi

########################################################

if [ $OSFLAVOUR == "debian" ]; then
    BOOT_PKG="linux-image-$ARCH grub-pc"
    repo=http://deb.debian.org/debian
    # reposecure=http://security.debian.org
    reposecure=http://deb.debian.org/debian-security
    components=main,contrib,non-free


    if [ $OSversion == testing ] ; then
        apt_source="
deb     ${repo} testing main contrib non-free
deb-src ${repo} testing main contrib non-free

deb     ${repo} testing-updates main contrib non-free
deb-src ${repo} testing-updates main contrib non-free

deb     ${reposecure} testing-security main contrib non-free
deb-src ${reposecure} testing-security main contrib non-free
"
    elif [ $OSversion == unstable ] ;then 
        apt_source="
#unstable  have no backport or security
deb     ${repo} unstable main contrib non-free
deb-src ${repo} unstable main contrib non-free
"
    else
        apt_source="
deb     ${repo} ${OSversion} main contrib non-free
deb-src ${repo} ${OSversion} main contrib non-free

deb     ${repo} ${OSversion}-updates main contrib non-free
deb-src ${repo} ${OSversion}-updates main contrib non-free

deb     ${repo} ${OSversion}-backports main contrib non-free
deb-src ${repo} ${OSversion}-backports main contrib non-free

deb     ${reposecure} ${OSversion}/updates main contrib non-free
deb-src ${reposecure} ${OSversion}/updates main contrib non-free
"

    fi


elif [ $OSFLAVOUR == "ubuntu" ]; then
    BOOT_PKG="linux-image-generic grub-pc"
    repo=http://archive.ubuntu.com/ubuntu
    # reposecure=http://security.ubuntu.com/ubuntu
    reposecure=http://archive.ubuntu.com/ubuntu
    components=main,restricted,universe,multiverse

    apt_source="
## universe multiverse is ENTIRELY UNSUPPORTED by the Ubuntu
deb ${repo}  ${OSversion} main restricted universe multiverse
deb ${repo}  ${OSversion}-updates main restricted universe multiverse
deb ${repo}  ${OSversion}-backports main restricted universe multiverse
deb ${reposecure} ${OSversion}-security main restricted universe multiverse

deb-src ${repo}  ${OSversion} main restricted universe multiverse
deb-src ${repo}  ${OSversion}-updates main restricted universe multiverse
deb-src ${repo}  ${OSversion}-backports main restricted universe multiverse
deb-src ${reposecure} ${OSversion}-security main restricted universe multiverse
"

fi

########################################################
INFOC ; echo "Looking for nbd device..." ; ENDC

modprobe nbd max_part=16

for i in /dev/nbd*
do
    if qemu-nbd -f ${ImgFormat} -c $i ${VMfile}
    then
        DISK=$i
        break
    fi
done

[ "$DISK" == "" ] && { WARNC ; echo "errorrr: no nbd device available" ; ENDC ; false ; }

INFOC ; echo "Connected ${VMfile} to $DISK" ; ENDC

########################################################
# partition image
########################################################
_msdos(){
    INFOC ; echo "partitioning..." ; ENDC
    parted --script ${DISK} mklabel msdos

    parted --align optimal ${DISK} mkpart primary 4096s 300MiB
    parted --align optimal ${DISK} mkpart primary 300MiB 1002MiB
    parted --align optimal ${DISK} mkpart primary 1002MiB 100%

    # Format a partition with the ext4 filesystem
    INFOC ; echo "Creating boot partition..." ; ENDC
    mkfs.ext4 -L boot   ${DISK}p1
    INFOC ; echo "Creating swap partition..." ; ENDC
    mkswap --label swap ${DISK}p2
    INFOC ; echo "Creating root partition..." ; ENDC
    mkfs.ext4 -L os     ${DISK}p3

    INFOC ; echo make ${DISK} bootable ; ENDC
    # 1 viene de sda1
    parted --script ${DISK} set 1 boot on
}
_msdos


INFOC ; echo "Mounting root partition..." ; ENDC
mount ${DISK}p3 $MNT_DIR

########################################################
INFOC ; echo "Installing $OSFLAVOUR $OSversion..." ; ENDC
mkdir -p /tmp/debootstrap_pkg/${OSFLAVOUR}_${OSversion}
debootstrap --merged-usr --cache-dir /tmp/debootstrap_pkg/${OSFLAVOUR}_${OSversion} --arch=amd64 --components=${components} --include=$common_packages $* $OSversion $MNT_DIR $repo

########################################################
# fstab
########################################################
INFOC ; echo "Configuring system..." ; ENDC
cat <<EOF > $MNT_DIR/etc/fstab
/dev/${DISKNAME}1 /boot               ext4    sync              0       2
/dev/${DISKNAME}2 none                swap    sw                0       0
/dev/${DISKNAME}3 /                   ext4    errors=remount-ro 0       1
EOF




########################################################
mountchrootMet1(){
mount -o bind,ro /dev   $MNT_DIR/dev
mount -t devpts devpts  $MNT_DIR/dev/pts
mount -t proc none      $MNT_DIR/proc
mount -t sysfs none     $MNT_DIR/sys
mount -t ext4 ${DISK}p1 $MNT_DIR/boot
}


mountchrootMet2(){
mount --bind /dev/ $MNT_DIR/dev
chroot $MNT_DIR mount -t devpts devpts /dev/pts
chroot $MNT_DIR mount -t ext4 ${DISK}p1 /boot
chroot $MNT_DIR mount -t proc none /proc
chroot $MNT_DIR mount -t sysfs none /sys
}

# mountchrootMet1 y mountchrootMet2 funcionan, usare 2 ya ke la guia original la usa
# mountchrootMet1
mountchrootMet2


########################################################
# kernel
########################################################

INFOC ; echo "Installing kernel" ; ENDC
# LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive chroot $MNT_DIR apt-get install -y --force-yes -q $BOOT_PKG

LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive chroot $MNT_DIR apt-get update
LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive chroot $MNT_DIR apt-get install -y $BOOT_PKG


INFOC ; echo "Installing bootloader" ; ENDC

serial_grub(){
    chroot $MNT_DIR grub-install $DISK
    
    # esto copie su mayoria de cloud-init grub config
    cat - >>$MNT_DIR/etc/default/grub <<S2EOF
### badr_grub ##############################
# recuerda ke si cambias algo ejecuta: update-grub

### Set the recordfail timeout ##########
# GRUB2 comes with a feature that, after a failed boot attempt, during the next boot will automatically stop at the boot menu.
# When previous boot was failed. (because of power failure, hardware failure) booting will hang at the grub menu for human prompt.
GRUB_RECORDFAIL_TIMEOUT=5

### wait on grub prompt ##########
GRUB_TIMEOUT=5

### Set the default commandline ##########
# GRUB_CMDLINE_LINUX_DEFAULT="console=tty1 console=ttyS0"
# quiet - this option tells the kernel to NOT produce any output (a.k.a. Non verbose mode). If you boot without this option, you'll see lots of kernel messages such as drivers/modules activations, filesystem checks and errors. Not having the quiet parameter may be useful when you need to find an error.
# net.ifnames=0 - disables Predictable Network Interface Names, osea usar eth0 en ves de ens0...
# GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200  net.ifnames=0  quiet"
GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200 earlyprintk=ttyS0,115200  net.ifnames=0"

### Set the grub console type ##########
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200"

# update-grub may detect and install boot entries of the host machine in the grub of this image; 
# https://github.com/drakkar-lig/debootstick/blob/43e4de78f6b2489f736fdd2441de48620f4fc0ee/scripts/create-image/target/pc/grub
GRUB_DISABLE_OS_PROBER=true
S2EOF

    chroot $MNT_DIR update-grub
}
serial_grub



sed -i "s|${DISK}p1|/dev/${DISKNAME}1|g" $MNT_DIR/boot/grub/grub.cfg
sed -i "s|${DISK}p2|/dev/${DISKNAME}2|g" $MNT_DIR/boot/grub/grub.cfg
sed -i "s|${DISK}p3|/dev/${DISKNAME}3|g" $MNT_DIR/boot/grub/grub.cfg


echo "Finishing grub installation..."
# met1:
grub-install $DISK --root-directory=$MNT_DIR --modules="biosdisk part_msdos"

# met2:esta no funiona!!! no veo nada al bootear
# grub-install $DISK 
# update-initramfs -u


########################################################
# config
########################################################
# Set root password
chroot $MNT_DIR bash -c "echo 'root:${ROOTPASSWD}' | chpasswd"
    
############################
# locale
############################
INFOC ; echo "configure locale" ; ENDC

chroot $MNT_DIR /bin/bash <<"EOF"

apt-get update
apt-get install -y locales

test -f /etc/locale_ORG.gen || cp /etc/locale.gen /etc/locale_ORG.gen
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen 

locale-gen --purge 'en_US.UTF-8'
update-locale 'LANG=en_US.UTF-8'
dpkg-reconfigure --frontend noninteractive locales
EOF

############################
# network
############################
INFOC ; echo "configure network" ; ENDC

test -f $MNT_DIR/etc/network/interfaces && cp $MNT_DIR/etc/network/interfaces $MNT_DIR/etc/network/interfacesORG
cat <<EOF > $MNT_DIR/etc/network/interfaces
auto lo
iface lo inet loopback

auto ${ETH_DEVICE}
iface ${ETH_DEVICE} inet dhcp
# ubuntu18 de debootstrap al configurar /etc/network/interfaces with dhcp it will run dhclient and leave it open listening on port 68 on 0.0.0.0
# pero no encontre nadie haciendolo pero funciona biennn
up pkill dhclient || true
EOF

############################
# hosts & hotname
############################
INFOC ; echo "configure hosts & hotname" ; ENDC

echo $HOSTNAME > $MNT_DIR/etc/hostname

cat <<EOF > $MNT_DIR/etc/hosts
127.0.0.1       localhost
127.0.1.1       $HOSTNAME
# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

############################
# dns
############################
INFOC ; echo "configure dns" ; ENDC
test -f $MNT_DIR/etc/resolv.conf && cp -a $MNT_DIR/etc/resolv.conf $MNT_DIR/etc/resolv.confORG

chroot $MNT_DIR systemctl disable systemd-resolved
chroot $MNT_DIR rm /etc/resolv.conf

echo '
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
 ' > $MNT_DIR/etc/resolv.conf

############################
# keyboard
############################
INFOC ; echo "Install/configure keyboard" ; ENDC
### get info abotu keyboard
# cat /usr/share/systemd/kbd-model-map
# localectl

# this steps will serve to configure the keyboard when you install keyboard-configuration for the first time, or when you have already installed it and you want to reconfigure it again.

chroot $MNT_DIR apt-get update
DEBIAN_FRONTEND=noninteractive chroot $MNT_DIR apt-get install -y console-setup keyboard-configuration

test -f $MNT_DIR/etc/default/keyboardORG || cp -a $MNT_DIR/etc/default/keyboard $MNT_DIR/etc/default/keyboardORG

# this is the trick, you have to change the default keyboard config before running dpkg-reconfigure or you will always end with what it is configured in /etc/default/keyboard, so for a french keyboard for example:

# remember this works with debian 10, debian testing (11),debian SID, ubuntu 16.04, ubuntu 18.04, ubuntu 20.04
# but do not work with ubuntu 16.04 because it does not have fr azerty but only fr,
# you can see the list of suported options (XKBLAYOUT, XKBVARIANT...) with:
# cat  /usr/share/X11/xkb/rules/xorg.lst | grep azerty
# so I have to remove XKBVARIANT="azerty"  in ubuntu 16 ,because dpkg-reconfigure will use its default us keyboard if there is any error in /etc/default/keyboard
if [ $OSversion == xenial ] ; then
    echo '
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT=""
XKBOPTIONS=""

BACKSPACE="guess"
' > $MNT_DIR/etc/default/keyboard

else
    echo '
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT="azerty"
XKBOPTIONS=""

BACKSPACE="guess"
' > $MNT_DIR/etc/default/keyboard
fi
    
chroot $MNT_DIR dpkg-reconfigure --frontend noninteractive keyboard-configuration

# remember I need to use tigervnc client to connect to the vnc implemented in qemu; los otros vnc clients no funcionan bien con el keyboard


############################
# apt source list
############################
test -f $MNT_DIR/etc/apt/sources.list && cp $MNT_DIR/etc/apt/sources.list $MNT_DIR/etc/apt/sources.listORG
echo "${apt_source}" > $MNT_DIR/etc/apt/sources.list


############################
# configure bash
############################
cat <<'EOF' > $MNT_DIR/etc/profile.d/badr_solve_vm_resize_and_color_serial_console.sh
#unix.stackexchange.com/questions/16578/resizable-serial-console-window/
res() {
  echo "===> resize serial console"
  old=$(stty -g)
  stty raw -echo min 0 time 5

  printf '\0337\033[r\033[999;999H\033[6n\0338' > /dev/tty
  IFS='[;R' read -r _ rows cols _ < /dev/tty

  stty "$old"

  # echo "cols:$cols"
  # echo "rows:$rows"
  stty cols "$cols" rows "$rows"
}

res2() {
  echo "===> resize serial console"
  old=$(stty -g)
  stty raw -echo min 0 time 5

  printf '\033[18t' > /dev/tty
  IFS=';t' read -r _ rows cols _ < /dev/tty

  stty "$old"

  # echo "cols:$cols"
  # echo "rows:$rows"
  stty cols "$cols" rows "$rows"
}

#esta me da error 
#[ $(tty) = /dev/ttyS0 ] && res2

# res funciona bien si la ejecuto in interactiive shell pero da error desde profile.d!
# res2 funciona bien de momento desde profile.d
res2

#lnav show no colors with vt220 (default); but works good with xterm and linux
#home and end buttons have no efect with linux using mintty (tested with journalctl) but xterm works good,creo es pk mintty usa xterm tb
#TERM=vt220
#TERM=linux
#TERM=xterm
TERM=xterm-256color   # lnav show better colors with this :)

EOF



# history
cat <<'EOF' > $MNT_DIR/etc/profile.d/badr_bash_profile.sh
#anadido por badr
alias grep='grep --color'
alias ls='ls --color=auto'

export HISTCONTROL=ignoreboth

# https://stackoverflow.com/questions/9457233/unlimited-bash-history
# Eternal bash history.
# ---------------------
# Undocumented feature which sets the size to "unlimited".
# http://stackoverflow.com/questions/9457233/unlimited-bash-history
# esto tiene un bug , si el fichero llega a 2gb bash volvera muy lentooo
# export HISTFILESIZE=
# export HISTSIZE=
# or
export HISTTIMEFORMAT="[%F %T] "
export HISTFILESIZE=9999
export HISTSIZE=1000

# Change the file location because certain bash sessions truncate .bash_history file upon close.
# http://superuser.com/questions/575479/bash-history-truncated-to-500-lines-on-each-login
export HISTFILE=~/.bash_eternal_history
# Force prompt to write history after every command.
# http://superuser.com/questions/20900/bash-history-loss
#PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

EOF




# PS1
# https://unix.stackexchange.com/questions/329581/why-is-debians-default-bash-shell-colourless
# http://www.linuxfromscratch.org/blfs/view/svn/postlfs/profile.html

# al crear un nuevo user a new .bashrc will be created wich contain PS1 and it will override this PS1 bellow (i can see what bash read with bash -lx or bash -x)
cat <<'EOF' >> $MNT_DIR/etc/skel/.bashrc

#badr_PS1
if [ ! -z "$PS1" ]; then
    NORMAL="\[\e[0m\]"
    RED="\[\e[1;31m\]"
    GREEN="\[\e[1;32m\]"
    if [[ $EUID == 0 ]] ; then
      PS1="$RED\u@\h [ $NORMAL\w$RED ]# $NORMAL"
    else
      PS1="$GREEN\u@\h [ $NORMAL\w$GREEN ]\$ $NORMAL"
    fi

    unset RED GREEN NORMAL
fi
EOF

# users already created will not have the content of /etc/skel/.bashrc so the following will force root user for example to have my PS1
cat <<'EOF' > $MNT_DIR/etc/profile.d/badr_PS1.sh
#badr_PS1
if [ ! -z "$PS1" ]; then
    NORMAL="\[\e[0m\]"
    RED="\[\e[1;31m\]"
    GREEN="\[\e[1;32m\]"
    if [[ $EUID == 0 ]] ; then
      PS1="$RED\u@\h [ $NORMAL\w$RED ]# $NORMAL"
    else
      PS1="$GREEN\u@\h [ $NORMAL\w$GREEN ]\$ $NORMAL"
    fi

    unset RED GREEN NORMAL
fi
EOF


# en ubuntu instalado por debootstrap viene con /root/.bashrc configurado con su PS1, asi ke vamos a anadir el PS1 a ello tb
cat <<'EOF' > $MNT_DIR/root/.bashrc
#badr_PS1
if [ ! -z "$PS1" ]; then
    NORMAL="\[\e[0m\]"
    RED="\[\e[1;31m\]"
    GREEN="\[\e[1;32m\]"
    if [[ $EUID == 0 ]] ; then
      PS1="$RED\u@\h [ $NORMAL\w$RED ]# $NORMAL"
    else
      PS1="$GREEN\u@\h [ $NORMAL\w$GREEN ]\$ $NORMAL"
    fi

    unset RED GREEN NORMAL
fi
EOF






########################################################
# take snapshot
########################################################


# TODO : does the snapshot introduce any overload over time? if yes then disable this step , i want it only to make tests so i can comeback to the original clean setup
umount_all
if [ ${ImgFormat} == qcow2 ]; then
    qemu-img snapshot -c "offline${datenowForHostname}-initial" ${VMfile}
fi

INFO2C ; echo "SUCCESS!" ; ENDC


########################################################
# creat qemu sripts
########################################################

# crea una copia de este script junto con la imagen por si acaso la necesito para saber como he creado la imagen
declare -f qemu_create_vm > qemu_create_vm.sh
echo "echo 'usage as script file: 
source qemu_create_vm.sh ; qemu_create_vm'" >> qemu_create_vm.sh
chmod +x qemu_create_vm.sh

# save qemu versions used:
echo ___qemu-system-x86_64____________________ > qemu.versions
qemu-system-x86_64 --version >> qemu.versions
echo ___qemu-img____________________ >> qemu.versions
qemu-img --version >> qemu.versions
echo ___qemu dependencies______________________ >> qemu.versions
apt show qemu-system-x86 >> qemu.versions


# create a config file containing the vm name and format so I can use them by qmm 
echo "VMname=${VMname}" > config.conf
echo "ImgFormat=${ImgFormat}" >> config.conf


# create the qemu command line 
cat <<'EOF' > run_${VMname}.sh

source config.conf
echo 'start virtual machine'

# if i kill qemu with kill -9 ,qemu will not delet the pid file. this will delete it if the pid file exist but there is not qemu running with that pid
test -d /run/MyQemu || mkdir /run/MyQemu
if test -f /run/MyQemu/${VMname}_pid ; then
    VM_pid=$(cat /run/MyQemu/${VMname}_pid)
    if [ ! -d /proc/${VM_pid} ] ; then
        echo zoombi PID found. cleaning...
        rm /run/MyQemu/${VMname}_pid /run/MyQemu/${VMname}_monitor.sock /run/MyQemu/${VMname}_serial.sock
    fi
fi

##### general ################################
OPTS="-name ${VMname}"
OPTS="$OPTS -m 2G"
OPTS="$OPTS -daemonize"
OPTS="$OPTS -enable-kvm"

##### CPU ####################################
OPTS="$OPTS -cpu host"

#Especially for Windows guests, enable Hyper-V enlightenments
# OPTS="$OPTS -cpu host,hv_relaxed,hv_spinlocks=0x1fff,hv_vapic,hv_time"

#lo usa proxmox to keep compatibility if a i change the host server so vm's will not have problems
# OPTS="$OPTS -cpu qemu64"

##### total cpus
# total_procs=cores=4,threads=2,sockets=1 # usa lscpu en el host para obtener estos
total_procs=$(nproc --all)
OPTS="$OPTS -smp ${total_procs}"

##### no elegire ninguna ya ke por defecto se usa pc
# OPTS="$OPTS -machine q35"
# OPTS="$OPTS -machine pc"
# OPTS="$OPTS -machine microvm"

##### pid & socks ############################
OPTS="$OPTS -pidfile /run/MyQemu/${VMname}_pid"
OPTS="$OPTS -monitor unix:/run/MyQemu/${VMname}_monitor.sock,server,nowait"
OPTS="$OPTS -serial unix:/run/MyQemu/${VMname}_serial.sock,server,nowait"
# OPTS="$OPTS -serial mon:stdio" # cannot use stdio with -daemonize

# ___control guest_______
OPTS="$OPTS -chardev socket,path=/run/MyQemu/${VMname}_qemuguestagent.sock,server,nowait,id=qga0"
OPTS="$OPTS -device virtio-serial"
OPTS="$OPTS -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"

# in guest do:
# apt install qemu-guest-agent
# systemctl start qemu-guest-agent

# execute commands in the guest from the host with
# git clone https://github.com/arcnmx/qemucomm
# or git clone https://github.com/badrelmers/qemucomm
# ./qemucomm -g /run/MyQemu/${VMname}_qemuguestagent.sock  exec -w -o bash -c 'ip a ; apt install lnav'

##### Drive ##################################
# always use -preallocation=full when creating qcow2 or raw images

aio_and_cache=",aio=native,cache=none"

# __________
# virtio-blk-pci with iothread. usa vda
OPTS="$OPTS -object iothread,id=myio1"
OPTS="$OPTS -device virtio-blk-pci,drive=mydisk0,iothread=myio1"
OPTS="$OPTS -drive file=${VMname}.${ImgFormat},if=none,id=mydisk0,format=${ImgFormat}${aio_and_cache}"
# o mas corto 
# OPTS="$OPTS -drive file=${VMname}.${ImgFormat},if=virtio,format=${ImgFormat}${aio_and_cache}"

# __________
# ide. usa sda
# OPTS="$OPTS -hda ${VMname}.${ImgFormat}"

# __________
# virtio-scsi with iothread. copiado de proxmox. usa sda
# num_queues=4 # this do more harm when bigguer
# OPTS="$OPTS -object iothread,id=iothread-virtio0" # necesito esta?
# OPTS="$OPTS -device pci-bridge,id=pci.1,chassis_nr=1,bus=pci.0,addr=0x1e"
# OPTS="$OPTS -device virtio-scsi-pci,id=scsihw0,bus=pci.0,addr=0x5,iothread=iothread-virtio0,num_queues=${num_queues}"
# OPTS="$OPTS -drive file=${VMname}.${ImgFormat},if=none,id=drive-scsi0,format=${ImgFormat}${aio_and_cache}"
# OPTS="$OPTS -device scsi-hd,bus=scsihw0.0,channel=0,scsi-id=0,lun=0,drive=drive-scsi0,id=scsi0"

##### share folder ###########################
share_folder(){
    # 9p shared directory
    # Another way of sharing files between a guest and the host which is simpler than NFS in its configuration is 9p.

    # This QEmu parameter shares the content of /badrshare on the host with the guest:
    # OPTS="$OPTS -virtfs local,id=fs0,mount_tag=badrshare,security_model=none,path=/badrshare"
    # or:
    OPTS="$OPTS -fsdev local,id=fs0,security_model=none,path=/badrshare"
    OPTS="$OPTS -device virtio-9p-pci,fsdev=fs0,mount_tag=badrshare"
    mkdir /badrshare
    # On the guest, /etc/fstab put the following line to mount the shared directory on /mnt/badrshare:
    # badrshare /mnt/badrshare 9p auto,trans=virtio,version=9p2000.L,_netdev 0 0
    # or mount temporarly
    # mkdir /tmp/badrshare
    # mount -t 9p -o trans=virtio,version=9p2000.L badrshare /tmp/badrshare
}
# share_folder

##### net #####################################
bridget_net(){
    #top performance:
    # modprobe vhost-net #no hace falta qemu lo hace
    OPTS="$OPTS -netdev tap,id=n1,br=vmbr0,helper=/usr/lib/qemu/qemu-bridge-helper,vhost=on"
    OPTS="$OPTS -device virtio-net,netdev=n1"

    #good performance
    #OPTS="$OPTS -net nic,model=virtio -net bridge,br=vmbr0"
    #lo mismo pero en una linea
    #OPTS="$OPTS -nic bridge,br=vmbr0,model=virtio"

    # usa e1000 interface, slow but do not need virtio dirver
    #OPTS="$OPTS -net nic -net bridge,br=vmbr0"
}
# bridget_net
# to activate user network comment bridget_net , i already configured guest net with dhcp arriba, esto usara la ip del host
# to activate bridge network uncomment bridget_net and configure the guest etc/network/interface with the second ip from hetzner
################################################


qemu-system-x86_64 ${OPTS}


EOF


chmod +x run_${VMname}.sh



INFO3C
echo "


===run with:============================================================
qmm run ${VMname}


"
ENDC


qemu_image_finished=finished


# fin del subshell
)


}




 # create a quick guide with the command I need to execute in the shell
 echo "

 
 
 
======================================================================================
usage:
qemu_create_vm   imagename                Hostname (a..Z y 0..9 y -)  OS    OS release
qemu_create_vm   buster${datenowForHostname}     buster${datenowForHostname}     debian   buster
qemu_create_vm   testing${datenowForHostname}    testing${datenowForHostname}    debian   bullseye
qemu_create_vm   testing${datenowForHostname}    testing${datenowForHostname}    debian   testing
qemu_create_vm   unstable${datenowForHostname}   unstable${datenowForHostname}   debian   unstable

qemu_create_vm   xenial${datenowForHostname}     xenial${datenowForHostname}     ubuntu   xenial
qemu_create_vm   bionic${datenowForHostname}     bionic${datenowForHostname}     ubuntu   bionic
qemu_create_vm   focal${datenowForHostname}      focal${datenowForHostname}      ubuntu   focal

"

