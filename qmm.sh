
 _install(){
# qmm: qemu manager
# author: Badr Elmers in 2021

test -d /run/MyQemu || mkdir /run/MyQemu
run_dir=/run/MyQemu


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

___get_vm_repo(){
    # puesto ke uso multiple repositories , necesito saber en ke repo esta el vm
    # usage: ___get_vm_repo VM
    # return the repository as $thisrepository
    local get_vm_repo_result=
    while read -r repository ; do
        if test -f "${repository}/${1}/run_${1}.sh" ; then
            thisrepository="${repository}"
            return
        else
            local get_vm_repo_result=no
        fi
    done < /etc/_qmm.conf
    [[ ${get_vm_repo_result} == no ]] && { WARNC ; echo "no VM folder was found with this name: ${1}" ; ENDC ; exit ; }
}



_list_running_vms(){
    echo repositories are:
    cat /etc/_qmm.conf
    echo ''

    # test if pid files exist then print names
    all_qm_pids=$(pidof qemu-system-x86_64)
    cd "${run_dir}"
    # echo "vm name                          vnc port"
    # echo ---------------------------------------------
    for i in *_pid ; do
        # test -f "${i}_pid" && { 
            _vm__name=$(echo "$i" | sed "s/_pid$//")
            VM_pid=$(cat ${run_dir}/${i} 2>/dev/null)
            _vnc__port=$(ss -tunlp --no-header | grep -F "pid=${VM_pid}" | grep 127.0.0.1:59 | cut -d : -f2 | cut -d ' ' -f1)
            alll=$(echo "$alll" ; echo "${_vm__name} ${_vnc__port}")
            
            # remove the pids of the running VM (VM_pid) from the list of all the qemu pids (all_qm_pids)
            VM_pid=$(cat ${run_dir}/${i} 2>/dev/null)
            all_qm_pids=$(echo "$all_qm_pids" | sed "s/$VM_pid//" 2>/dev/null)
        # }
    done

    printf "VM_name vnc_port\n_______________ _______\n $alll\n" | column -t
    
    all_qm_pids_sin_espacio=$(echo "${all_qm_pids}" | tr -d '[:space:]')
    # test ps for qemu images that i may have run without qemu pid flag and print in yellow
    [[ "$all_qm_pids_sin_espacio" == "" ]] || { WARNC ; echo 'there is some qemu running and is not managed by qmm' ; echo "pids: $all_qm_pids" ; ENDC ; }
}

_list_vm_images(){
    while read -r repository ; do
        echo ''
        echo "====================================================" 
        echo "repository: ${repository}"
        echo "===================================================="
        cd "${repository}"
        echo 'Size    VM Name'
        echo ------------------------------
        du -chs *
    done < /etc/_qmm.conf
}

_vm_info(){
    INFOC ; echo get VM info ; ENDC
    ___get_vm_repo ${1}
    cd "${thisrepository}/${1}"
    source config.conf
    echo "
    Repo: ${thisrepository}/${1}
    Format: ${ImgFormat}
    Size: $(du -chs ${1}.${ImgFormat} | grep ${1})
    "
}

_start_vm(){
    # if i kill qemu with kill -9 ,qemu will not delet the pid file. this will delete it if the pid file exist but there is not qemu running with that pid
    if test -f ${run_dir}/${1}_pid ; then
        VM_pid=$(cat ${run_dir}/${1}_pid)
        if [ ! -e /proc/${VM_pid}/comm ] ; then
            INFO3C ; echo zoombi PID found. cleaning... ; ENDC
            rm ${run_dir}/${1}_pid ${run_dir}/${1}_monitor.sock ${run_dir}/${1}_serial.sock
        fi
    fi

    # check if vm is already running
    if [ -f ${run_dir}/${1}_pid ] ; then
        WARNC ; echo VM seems already running ; ENDC
        return 0
    fi
    
    # run the vm  
    ___get_vm_repo "${1}"
    cd "${thisrepository}/${1}"
    "${thisrepository}/${1}/run_${1}.sh"
            
    pidreturn=
    # check if the pid file created successfully
    if [ ! -f ${run_dir}/${1}_pid ] ; then
        sleep 1
    fi
    if [ ! -f ${run_dir}/${1}_pid ] ; then
        pidreturn=error
    fi
    # check if the process started successfully
    if [ ! -e /proc/$(cat ${run_dir}/${1}_pid)/comm ] ; then
        pidreturn=error
    fi

    if [[ "$pidreturn" = "error" ]] ; then
        ERRORC ; echo "startup failed. mira pk" ; ENDC
        return 1
    else
        INFOC ; echo "startup successfully" ; ENDC
    fi
}

_run_vm(){
    _start_vm ${1}
    _connect_to_console ${1}
}

###########################################
### power managment
###########################################
# q|quit  -- quit the emulator, Quit QEMU immediately.

# sendkey ctrl-alt-delete
# sendkey keys [hold_ms] -- send keys to the VM (e.g. 'sendkey ctrl-alt-f1', default hold time=100 ms)
# You can emulate keyboard events through sendkey command. The syntax is: sendkey keys. To get a list of keys, type sendkey [tab].

# system_powerdown  -- send system power down event, This has an effect similar to the physical power button on a modern PC. The VM will get an ACPI shutdown request and usually shutdown cleanly.

# system_reset  -- reset the system, This has an effect similar to the physical reset button on a PC. Warning: Filesystems may be left in an unclean state.


# stop  -- stop emulation, Suspend execution of VM
# cont     Reverse a previous stop command - resume execution of VM.
                
_stop_vm(){
    INFOC ; echo "stop VM" ; ENDC

    VM_pid=$(cat ${run_dir}/${1}_pid)
    # send soft shutdown
    if [ -e /proc/${VM_pid}/comm ] ; then
        echo "system_powerdown" | socat - UNIX-CONNECT:${run_dir}/${1}_monitor.sock
        echo ""
    else
        echo VM is not running
        return
    fi

    delay=0
    while : ; do
        if [ -e /proc/${VM_pid}/comm ] ; then
            echo waiting $((15-$delay))s...
            sleep 1
            delay=$(($delay+1))
            if test $delay -gt 15 ; then
                WARNC ; echo force hard kill VM... ; ENDC
                echo "system_reset" | socat - UNIX-CONNECT:${run_dir}/${1}_monitor.sock
                sleep 1
                break
            fi
        else
            echo VM stoped.
            break
        fi
    done
        
    # if the process is still running
    # send command quit to its monitor, and wait
    if [ -e /proc/${VM_pid}/comm ] ; then
        WARNC ; echo "force hard kill qemu (monitor quit)..." ; ENDC
        echo "quit" | socat - UNIX-CONNECT:${run_dir}/${1}_monitor.sock
        sleep 1
    fi

    # check if the process is still running and kill qemu with kill -9 , killin qemu like that will prevent qemu from cleaning pid and socks files , so here i clean them manually
    if [ -e /proc/${VM_pid}/comm ] ; then
        _kill_vm ${1}
    fi
}

_kill_vm(){
    VM_pid=$(cat ${run_dir}/${1}_pid)

    # if the process is still running, kill it
    if [ -e /proc/${VM_pid}/comm ] ; then
        WARNC ; echo "hard kill qemu proc with kill -9" ; ENDC
        kill -9 ${VM_pid}
        rm ${run_dir}/${1}_pid
        rm ${run_dir}/${1}_monitor.sock
        rm ${run_dir}/${1}_serial.sock
        echo "VM killed"
        return
    else
        echo VM is not running. there is nothing to kill
        return
    fi
}

_edit_vm(){    
    ___get_vm_repo "${1}"
    nano "${thisrepository}/${1}/run_${1}.sh"
}

###########################################
### snapshots
###########################################
# if vm is running I cannot use qemu-img but savevm. i will call it live snapshot
# if vm is stopped I cannot use savevm but qemu-img. I will call it offline snapshot
# I cannot restore an offline qemu-img snapshot with loadvm
# I can restore a live snapshot with qemu-img 

# _________________
# live snapshots
# _________________

_take_live_snapshot(){    
    # VM snapshots are snapshots of the complete virtual machine including CPU state, RAM, device state and the content of all the writable disks. In order to use VM snapshots, you must have at least one non removable and writable block device using the qcow2 disk image format. Normally this device is the first virtual hard drive.

    # Use the monitor command savevm to create a new VM snapshot or replace an existing one. A human readable name can be assigned to each snapshot in addition to its numerical ID.

    # Use loadvm to restore a VM snapshot and delvm to remove a VM snapshot. info snapshots lists the available snapshots with their associated information:

    # A VM snapshot is made of a VM state info (its size is shown in info snapshots) and a snapshot of every writable disk image. The VM state info is stored in the first qcow2 non removable and writable block device. The disk image snapshots are stored in every disk image. The size of a snapshot in a disk image is difficult to evaluate and is not shown by info snapshots because the associated disk sectors are shared among all the snapshots to save disk space (otherwise each snapshot would need a full copy of all the disk images).

    INFOC ; echo take a live snapshot ; ENDC
    datenow=$(date +%Y%m%d%H%M%S)
    echo "savevm live${datenow}-$2" | socat - UNIX-CONNECT:${run_dir}/${1}_monitor.sock
    
    # INFOC ; echo list all snapshots: ; ENDC
    # no hagas esto aki pk si el disco es lento no funcionara ; no se pk pasa eso
    # bash -c "echo 'info snapshots' | socat - UNIX-CONNECT:${run_dir}/${1}_monitor.sock"
}

_list_live_snapshots(){
    INFOC ; echo list of available live snapshots: ; ENDC
    echo 'info snapshots' | socat - UNIX-CONNECT:${run_dir}/${1}_monitor.sock
}

_restore_live_snapshot(){
    INFOC ; echo restore a live VM snapshot ; ENDC
    echo "loadvm $2" | socat - UNIX-CONNECT:${run_dir}/${1}_monitor.sock
}

_remove_live_snapshot(){
    INFOC ; echo remove a live VM snapshot ; ENDC
    echo "delvm $2" | socat - UNIX-CONNECT:${run_dir}/${1}_monitor.sock
}

# _________________
# offline snapshots
# _________________
_take_offline_snapshot(){
    INFOC ; echo take offline snapshot ; ENDC
    ___get_vm_repo "${1}"
    VM_pid=$(cat ${run_dir}/${1}_pid 2>/dev/null)
    datenow=$(date +%Y%m%d%H%M%S)    
    
    if [ ! -e /proc/${VM_pid}/comm ] ; then
        cd "${thisrepository}/${1}"
        source config.conf
        [[ "${ImgFormat}" == qcow2 ]] || { WARNC ; echo "${ImgFormat} is not supported. only qcow2" ; ENDC ; return ; }
        qemu-img snapshot -c "offline${datenow}-$2" "${1}.${ImgFormat}"
    else
        WARNC ; echo VM is running. stop it first to use the offline snapshot method or use the live snapshot method; ENDC
    fi
}

_list_offline_snapshots(){
    INFOC ; echo list of available snapshots: ; ENDC
    ___get_vm_repo "${1}"
    VM_pid=$(cat ${run_dir}/${1}_pid 2>/dev/null)
    
    if [ ! -e /proc/${VM_pid}/comm ] ; then
        cd "${thisrepository}/${1}"
        source config.conf
        # qemu-img snapshot -l "${1}.${ImgFormat}"
        # or
        qemu-img info "${1}.${ImgFormat}"
    else
        WARNC ; echo VM is running. stop it first to use the offline snapshot method or use the live snapshot method; ENDC
    fi
}

_restore_offline_snapshot(){
    INFOC ; echo restore an offline VM snapshot ; ENDC
    ___get_vm_repo "${1}"
    VM_pid=$(cat ${run_dir}/${1}_pid 2>/dev/null)
    
    if [ ! -e /proc/${VM_pid}/comm ] ; then
        cd "${thisrepository}/${1}"
        source config.conf
        [[ "${ImgFormat}" == qcow2 ]] || { WARNC ; echo "${ImgFormat} is not supported. only qcow2" ; ENDC ; return ; }
        qemu-img snapshot -a "$2" "${1}.${ImgFormat}"
    else
        WARNC ; echo VM is running. stop it first to use the offline snapshot method or use the live snapshot method; ENDC
    fi
}

_remove_offline_snapshot(){
    INFOC ; echo remove an offline VM snapshot ; ENDC
    ___get_vm_repo "${1}"
    VM_pid=$(cat ${run_dir}/${1}_pid 2>/dev/null)
    
    if [ ! -e /proc/${VM_pid}/comm ] ; then
        cd "${thisrepository}/${1}"
        source config.conf
        [[ "${ImgFormat}" == qcow2 ]] || { WARNC ; echo "${ImgFormat} is not supported. only qcow2" ; ENDC ; return ; }
        qemu-img snapshot -d "$2" "${1}.${ImgFormat}"
    else
        WARNC ; echo VM is running. stop it first to use the offline snapshot method or use the live snapshot method; ENDC
    fi
}



# _________________
_clone_vm(){
    # clone a vm and name it oldname_clone_$date
    VM_pid=$(cat ${run_dir}/${1}_pid 2>/dev/null)
    datenow=$(date +%Y%m%d%H%M%S)
    
    # if the process is still running, kill it
    if [ ! -e /proc/${VM_pid}/comm ] ; then
        INFOC ; echo clone VM ; ENDC
        ___get_vm_repo "${1}"    
        if test -f "${thisrepository}/${1}/run_${1}.sh" ; then
            cp -a "${thisrepository}/${1}" "${thisrepository}/${1}-clone-${datenow}"
            cd "${thisrepository}/${1}-clone-${datenow}"
            sed -i "s/${1}/${1}-clone-${datenow}/" config.conf
            source config.conf
            mv "${1}.${ImgFormat}" "${1}-clone-${datenow}.${ImgFormat}"
            mv "run_${1}.sh" "run_${1}-clone-${datenow}.sh"
        fi
    else
        WARNC ; echo VM is running. stop it first ; ENDC
    fi
}


########################################
### Connect to console
########################################
_connect_to_console(){
    # clear
    
    ps aux | grep -v grep | grep "socat.*${1}_serial.sock" && { WARNC ; echo there is another socat connected to the sock, no podras conectar otra vez. cierra el otro primero o mata socat ; }
    
    # in escape use the hexadecimal representation of a byte http://www.physics.udel.edu/~watson/scen103/ascii.html
    # +o  lo usa nano para guardar, +k lo usa bash para borrar last word ; +n lo usa bash como up/down asi ke la usare
    INFO3C ; echo 'use ctrl+n to breakout. press enter to see the prompt if not visible' ; ENDC
    socat -,raw,echo=0,escape=0x0e UNIX-CONNECT:${run_dir}/${1}_serial.sock 
    # socat stdin,raw,echo=0,escape=0x11 "unix-connect:${SOCKET}"
}

########################################
### Connect to monitor
########################################
_connect_to_monitor(){
    # clear
    
    ps aux | grep -v grep | grep "socat.*${1}_monitor.sock" && { WARNC ; echo there is another socat connected to the sock, no podras conectar otra vez. cierra el otro primero o mata socat ; }
    
    # in escape use the hexadecimal representation of a byte http://www.physics.udel.edu/~watson/scen103/ascii.html
    INFO3C ; echo 'use ctrl+n to breakout. press enter to see the prompt if not visible' ; ENDC
    socat -,raw,echo=0,escape=0x0e UNIX-CONNECT:${run_dir}/${1}_monitor.sock
}


_delete_vm(){
    if [ $# -lt 1 ] ; then
        WARNC ; echo "usage: qmm deletevm VM" 1>&2 ; ENDC
        return
    fi
    
    INFOC ; echo delete VM ; ENDC
    VM_pid=$(cat ${run_dir}/${1}_pid 2>/dev/null)

    # if the process is still running, kill it
    if [ ! -e /proc/${VM_pid}/comm ] ; then
        ___get_vm_repo "${1}"
        
        WARNC ; echo "I will delete this folder:"
        echo "   => ${thisrepository}/${1} <="
        ENDC
        read -p "Continue (y/n)?" choice
        case "$choice" in 
            y|Y ) rm -rf "${thisrepository}/${1}";;
            n|N ) return;;
            * ) echo "invalid choice";;
        esac
    else
        WARNC ; echo VM is running. stop it first ; ENDC
    fi
}


_rename_vm(){
    if [ $# -lt 2 ] ; then
        WARNC ; echo "usage: qmm rename VM NewName" 1>&2 ; ENDC
        return
    fi

    VM_pid=$(cat ${run_dir}/${1}_pid 2>/dev/null)
    
    # if the process is still running, kill it
    if [ ! -e /proc/${VM_pid}/comm ] ; then
        INFOC ; echo rename VM ; ENDC
        ___get_vm_repo "${1}"
        if test -f "${thisrepository}/${1}/run_${1}.sh" ; then
            mv "${thisrepository}/${1}" "${thisrepository}/${2}"
            cd "${thisrepository}/${2}"
            sed -i "s/${1}/${2}/" config.conf
            source config.conf
            mv "${1}.${ImgFormat}" "${2}.${ImgFormat}"
            mv "run_${1}.sh" "run_${2}.sh"
        fi
    else
        WARNC ; echo VM is running. stop it first ; ENDC
    fi
}

_exec_command(){
    # execute commands in the guest from the host
    if ! test -f /usr/local/bin/qemucomm ; then
        INFOC ; echo install qemucomm ; ENDC
        # git clone https://github.com/arcnmx/qemucomm
        # git clone https://github.com/badrelmers/qemucomm
        wget https://raw.githubusercontent.com/badrelmers/qemucomm/master/qemucomm -O /usr/local/bin/qemucomm
        chmod +x /usr/local/bin/qemucomm
    fi
    INFOC ; echo execute command inside VM ; ENDC
    qemucomm -g /run/MyQemu/${1}_qemuguestagent.sock  exec -w -o bash -c "${2}"
}


_autorun_vm(){
    INFOC ; echo autorun VM using systemd ; ENDC
    # https://unix.stackexchange.com/questions/47695/how-to-write-startup-script-for-systemd
    # https://serverfault.com/questions/904346/wait-for-service-to-gracefully-exit-before-machine-shutdown-reboot
    # How do you make a systemd service as the last service on boot?
    # In systemd it is advised to use Before= and After= to order your services nicely around the other ones.
    # But since you asked for a way without using Before and After, you can use:
    # Type=idle
    # which as man systemd.service explains:
    # Behavior of idle is very similar to simple; however, actual execution of the service program is delayed until all active jobs are dispatched. This may be used to avoid interleaving of output of shell services with the status output on the console. Note that this type is useful only to improve console output, it is not useful as a general unit ordering tool, and the effect of this service type is subject to a 5s timeout, after which the service program is invoked anyway.
    
    ___get_vm_repo "${1}"
    if test -f "${thisrepository}/${1}/run_${1}.sh" ; then
        echo "
[Unit]
Description=VM: ${1} - qmm QEMU manager
[Service]
Type=idle
ExecStart=/bin/bash -c 'qmm start ${1}'
ExecStop=/bin/bash -c 'qmm stop ${1}'
RemainAfterExit=yes
TimeoutStopSec=5
[Install]
WantedBy=multi-user.target
        " > /etc/systemd/system/qmm_${1}.service
        systemctl enable qmm_${1}.service
    else
        WARNC ; echo "no VM found with this name: ${1}" ; ENDC
    fi
}

_autorundisable_vm(){
    INFOC ; echo disable VM autorun ; ENDC
    systemctl disable qmm_${1}.service
    rm /etc/systemd/system/qmm_${1}.service
}

_listautorun(){
    INFOC ; echo list all autorun VMs services ; ENDC
    systemctl | grep -F 'qmm_'
    INFOC ; echo list all autorun VMs services files; ENDC
    ls /etc/systemd/system/qmm_* 2>/dev/null
}


# TODOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO
_connect_to_ssh(){
    echo TODO
}

_connect_to_vnc(){
    echo TODO
}


_help(){
    echo '
    config file: /etc/_qmm.conf
    ============================
    list,ls                                list running VMs
    listimages,lsi                         list all VM images in the repository
    info <VM>                              print VM info (location, image format, size)
    
    run <VM>                               start VM and connect to it by serial console
    start <VM>                             start VM
    stop <VM>                              stop VM (clean)
    kill <VM>                              kill VM (force stop)
    
    edit <VM>                              edit VM config
    
    shell,sh <VM>                          connect to serial
    mon <VM>                               connect to monitor
    ssh <VM>                               connect to ssh
    vnc <VM>                               connect to vnc
    
    exec <VM> "command"                    execute command inside VM using Guest Agent in bash
    
    listsnapshotsLive <VM>                    list Live snapshots of VM
    takesnapshotLive <VM> <optional name>     take a Live snapshot of VM
    restoresnapshotLive <VM> <snapshot>       restore a Live snapshot of VM
    removesnapshotLive <VM> <snapshot>        remove a Live snapshot of VM
    
    listsnapshotsOffline <VM>                 list Offline snapshots of VM
    takesnapshotOffline <VM> <optional name>  take an Offline snapshot of VM
    restoresnapshotOffline <VM> <snapshot>    restore an Offline snapshot of VM
    removesnapshotOffline <VM> <snapshot>     remove an Offline snapshot of VM
    
    clone <VM>                             clone a VM
    
    autorun <VM>                           create systemd service to autorun the image at boot
    autorundisable <VM>                    remove systemd autorun service
    listautorun                            list all autorun VM services
    
    rename <VM> <new name>                 rename VM
    deletevm <VM>                          delete VM completly
    
    help,h                                 show help
    '
}

########################################
### main 
########################################
RETVAL=0

cmd=$1
# shift


case "$cmd" in
    list|ls)
        _list_running_vms
        ;;
    listimages|lsi)
        _list_vm_images
        ;;
    info)
        _vm_info "$2"
        ;;
    start)
        _start_vm "$2"
        ;;
    run)
        _run_vm "$2"
        ;;
    stop)
        _stop_vm "$2"
        ;;
    kill)
        _kill_vm "$2"
        ;;
    edit)
        _edit_vm "$2"
        ;;
    shell|sh)
        _connect_to_console "$2"
        ;;
    mon)
        _connect_to_monitor "$2"
        ;;
    ssh)
        _connect_to_ssh "$2"
        ;;
    vnc)
        _connect_to_vnc "$2"
        ;;
    exec)
        _exec_command "$2" "$3"
        ;;
    listsnapshotsLive)
        _list_live_snapshots "$2"
        ;;
    takesnapshotLive)
        _take_live_snapshot "$2" "$3"
        ;;
    restoresnapshotLive)
        _restore_live_snapshot "$2" "$3"
        ;;
    removesnapshotLive)
        _remove_live_snapshot "$2" "$3"
        ;;
    listsnapshotsOffline)
        _list_offline_snapshots "$2"
        ;;
    takesnapshotOffline)
        _take_offline_snapshot "$2" "$3"
        ;;
    restoresnapshotOffline)
        _restore_offline_snapshot "$2" "$3"
        ;;
    removesnapshotOffline)
        _remove_offline_snapshot "$2" "$3"
        ;;
    clone)
        _clone_vm "$2"
        ;;
    autorun)
        _autorun_vm "$2"
        ;;
    autorundisable)
        _autorundisable_vm "$2"
        ;;
    listautorun)
        _listautorun
        ;;
    rename)
        # do not quote $3 sino no me funcionara el test con $# para saber cuantos parametros fueron pasados
        _rename_vm "$2" $3
        ;;
    deletevm)
        # do not quote $3 sino no me funcionara el test con $# para saber cuantos parametros fueron pasados
        _delete_vm $2
        ;;
    help|h)
        _help
        ;;
    *)
        WARNC ; echo "Unknown command: "$cmd. >&2 ; ENDC
        _help
        ;;
esac

exit $RETVAL
 }

 # _____________________________________________________



 # install the script 
 declare -f _install > /usr/local/bin/qmm

 # declare will put the function as function in the file so let s solve it;so it will not run if it s not called 
 prepare_script(){
    met1_prepare(){
        # met1:this will remove the function parts
        # delet first two lines
        sed -i '1,2d' /usr/local/bin/qmm
        # delete last line
        sed -i '$d' /usr/local/bin/qmm
    }
    # met1_prepare
    
    met2_prepare(){
        # met2:call the function
        echo '_install "$@"' >> /usr/local/bin/qmm
    }
    met2_prepare
 }
 prepare_script
 
 chmod +x /usr/local/bin/qmm

 
 
