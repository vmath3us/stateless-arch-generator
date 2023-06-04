#!/bin/bash
home_user=$HOME
current_dir=$(readlink -f $(pwd))
img_file="Arch_Stateless.img"
root_size="5"  ###################### root size img in GB
cache_img_file="pacman_cache.img"
cache_size="5"  ###################### pacman cache size img in GB
git_clone_dir="$current_dir/git-clone"
nocow_dir="$current_dir/iso-download"
initrd_build_dir="$nocow_dir/initrd-build"
pacman_cache="pod-Arch-cache-volume"
###################################---on host start---#############################################
###################################---on host start---#############################################
###################################---on host start---#############################################
###################################---on host start---#############################################
###################################---on host start---#############################################
###################################---on host start---#############################################
if_exists(){
    podman container exists pod-Arch && exists || not_exists
}
not_exists(){
provisioning_kvm_exec && exists || printf "não foi possível usar o podman" && exit 1
}
exists(){
    container_entry && stop_setup || stop_setup
}
provisioning_kvm_exec(){
    printf "\ngerando container..."
    mkdir  -p $nocow_dir &&
    chattr +C $nocow_dir    ########################## cow dirs causes kernel-panic on qemu -kernel
kvm_podman_command="podman create
                    --net host
                    --privileged
                    --security-opt label=disable
                    --name pod-Arch
                    --volume $current_dir:$current_dir
                    --volume $pacman_cache:/var/cache/pacman/pkg
                    --volume /dev/kvm:/dev/kvm:rslave
                    -it archlinux"
    eval ${kvm_podman_command}
}
container_entry(){
    podman start pod-Arch &&
    podman exec \
    --workdir=$current_dir \
    --tty \
    --interactive \
    --detach-keys="" \
    pod-Arch $current_dir/SA_Generator.sh
}
stop_setup(){
printf "\nparando container...%s\n"
    podman stop pod-Arch
}
####################################---on host end---##############################################
####################################---on host end---##############################################
####################################---on host end---##############################################
####################################---on host end---##############################################
####################################---on host end---##############################################
####################################---on host end---##############################################






##############################---on container start---#############################################
##############################---on container start---#############################################
##############################---on container start---#############################################
##############################---on container start---#############################################
##############################---on container start---#############################################
##############################---on container start---#############################################
on_pod_run(){
    pod_entrypoint &&
    disk_create &&
    download_files &&
    hash_verify &&
    initrd_create &&
    qemu_run &&
    disk_verify &&
    boot_new_arch &&
    boot_instructions && return 0 || exiting_status_print && return 1
}
pod_entrypoint(){
    printf "\nbaixando e instalando dependências\n"
exiting_log="deps"
if ! command -v qemu-img || ! command -v qemu-system-x86_64 || ! command -v sgdisk || ! command -v aria2c || ! command -v git ; then
    sed -i -e "s|ParallelDownloads.*|ParallelDownloads = 15\nDisableDownloadTimeout\nILoveCandy|g" -e "s|NoProgressBar||g" /etc/pacman.conf
    pacman -Syu qemu-hw-display-qxl spice spice-protocol qemu-img qemu-system-x86 gptfdisk aria2 git --noconfirm --needed
    fi &&
        if [ -d $git_clone_dir ] ; then rm -rf $git_clone_dir ; fi &&
        mkdir -p $git_clone_dir &&
        git clone https://gitlab.com/vmath3us/stateless-arch $git_clone_dir &&
        tar --owner=0 --group=0 -cf \
        $current_dir/stateless-arch.tar \
        -C $git_clone_dir etc usr
        return
}
disk_create(){
    printf "\ncriando arquivos imagem de suporte\n"
    mkdir -p $nocow_dir &&  ###### recreate if user delete dirs
    chattr +C $nocow_dir    ########################## cow dirs causes kernel-panic on qemu -kernel
exiting_log="create-disk"
plb_cache="pacmancache"           ### partlabel is gpt flag
splb_cache="validcache"           ### partlabel is gpt flag
plb_legacy="grub_legacy"
plb_efi="grub_efi"
plb_root="ArchLinux"
plb_control="initial"
splb_control="installed"
   ###################### store pacman_cache on host
   if [ ! -f $nocow_dir/$cache_img_file ] || ! $(sfdisk -d $nocow_dir/$cache_img_file | grep $splb_cache >/dev/null) ; then
        qemu-img create -f raw $nocow_dir/$cache_img_file "$cache_size"G && 
        sgdisk --zap-all $nocow_dir/$cache_img_file &&
        sgdisk --new=1:0:-2M -c 1:$plb_cache $nocow_dir/$cache_img_file
    fi
   ###################### store pacman_cache on host
   #####################create root image
    if [ ! -f $nocow_dir/$img_file ] ; then
        qemu-img create -f raw $nocow_dir/$img_file "$root_size"G &&
        sgdisk --zap-all $nocow_dir/$img_file &&
        sgdisk --new=1:0:+2M --new=2:0:+50M --new=3:0:-2M --new 4:0:0 --typecode=1:0xEF02 --typecode=2:0xEF00 $nocow_dir/$img_file &&
        sgdisk -c 1:$plb_legacy -c 2:$plb_efi -c 3:$plb_root -c 4:$plb_control $nocow_dir/$img_file
    else 
        if ! $(sfdisk -d $nocow_dir/$img_file | grep $splb_control >/dev/null) ; then
            rm -rf $nocow_dir/$img_file && disk_create ##### loop to create new disk
        else
         zero_img="1"
         printf "\nJá existe uma instalação reportada como bem sucedida\nDestruir? zero para sim %s\n"
                read -s -n1 zero_img </dev/tty
                if [ $zero_img == "0" ] ; then
                    rm -rf $nocow_dir/$img_file
                    disk_create   ##### loop to create new disk
                else
                    printf "a instalação atual foi preservada\n"
                    preserved_setup
                    exiting_log="preserved"
                    return 1
                fi
        fi
    fi
    return
}
download_files(){
###### this links is static because ArchPXE  https://archlinux.org/releng/netboot/
    printf "baixando arquivos...\n"
exiting_log="download"
hash_table="https://geo.mirror.pkgbuild.com/iso/latest/sha256sums.txt"
iso_link='https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso'
kernel_link='https://geo.mirror.pkgbuild.com/iso/latest/arch/boot/x86_64/vmlinuz-linux'
initrd_link='https://geo.mirror.pkgbuild.com/iso/latest/arch/boot/x86_64/initramfs-linux.img'
################ ever download hashtable
if [ -f $nocow_dir/sha256sums.txt ] ; then rm -rf $nocow_dir/sha256sums.txt ; fi &&
    aria2c $hash_table -d $nocow_dir &&
    for i in $iso_link $kernel_link $initrd_link; do
        aria2c --continue=true --auto-file-renaming=false $i -d $nocow_dir
    done
    return
}
hash_verify(){
    exiting_log="isohash"
    printf "verificando hash da iso...\n"
    real_hash=$(sha256sum $nocow_dir/archlinux-x86_64.iso | cut -d " " -f1)
    wanted_hash=$(awk '/archlinux-x86_64.iso/ {print $1}' $nocow_dir/sha256sums.txt) 
        if [ "$wanted_hash" == "$real_hash" ] ; then
            return 0
        else
            iso_fix="1"
            printf "hash da iso incorreto\napagar e baixar novamente? zero para sim:%s\n"
            read -n1 -r iso_fix </dev/tty
            if [ $iso_fix == "0" ] ; then
                rm -rf $nocow_dir/vmlinuz-linux \
                    $nocow_dir/archlinux-x86_64.iso \
                    $nocow_dir/initramfs-linux.img && 
                download_files && return 0 || printf "não foi possível apagar os arquivos, saindo%s\n"; return 1 
            else
                printf "abortando e saindo com status de erro%s\n" ; return 1
            fi
        fi
        return
}
initrd_create(){
exiting_log="create-initrd"
printf "gerando initrd customizado...\n"
        mkdir -p $initrd_build_dir
        cd $initrd_build_dir &&
        bsdtar -xf $nocow_dir/initramfs-linux.img &&
        mkdir -p $initrd_build_dir/root/etc/systemd/system/serial-getty@ttyS0.service.d/ &&
        cp $current_dir/SA_Generator.sh $initrd_build_dir/root/. &&
        cp $current_dir/packagelist.pacman $initrd_build_dir/root/. &&
        cp $current_dir/stateless-arch.tar $initrd_build_dir/root/. &&
cat  > $initrd_build_dir/root/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --autologin root --keep-baud 115200,57600,38400,9600 %I \$TERM
EOF
printf './SA_Generator.sh' > $initrd_build_dir/root/.zshrc &&
sed "s|exec env -i|cp /root/stateless-arch.tar /root/SA_Generator.sh /root/packagelist.pacman /root/.zshrc /new_root/root/.\nrm -rf /new_root/etc/systemd/system/getty@*\ncp -r /root/etc/systemd/* /new_root/etc/systemd/.\nexec env -i|" -i $initrd_build_dir/init &&
        unlink var/run &&
        find . -mindepth 1 -printf '%P\0' | sort -z | bsdtar --uid 0 --gid 0 --nul -cnf - -T - | bsdtar --null -cf - --format=newc @- | zstd -T0f3c > $nocow_dir/pod-Arch-init.img
        return
}
qemu_run(){
current_iso=$(file $nocow_dir/archlinux-x86_64.iso | awk '{print $10}' | sed "s/'//g" -)
exec_qemu="1"
        qemu_command="qemu-system-x86_64
                      -enable-kvm
                      -smp 2
                      -m 4096
                      -boot menu=on
                      -cpu host
                      -bios /usr/share/ovmf/x64/OVMF.fd
                      -nographic
                      -kernel $nocow_dir/vmlinuz-linux
                      -append \"archisobasedir=arch archisolabel=$current_iso console=ttyS0 systemd.mask=pacman-init.service systemd.mask=reflector.service\"
                      -initrd $nocow_dir/pod-Arch-init.img
                      -cdrom $nocow_dir/archlinux-x86_64.iso
                      -drive format=raw,file=$nocow_dir/$img_file
                      -drive format=raw,file=$nocow_dir/$cache_img_file"
exiting_log="qemu-user-abort" 
##### mask pacman-init to control manually pacman-key process
    for i in {10..1} ; do
        clear
        printf "\no qemu irá iniciar agora,\nusando dois núcleos e 4GB de RAM\n\n\nao concluir o boot, a instalação comecará.\n\niniciando em "$i"s%s\n\nctrl-c para cancelar"
        sleep 1
    done && eval ${qemu_command} && return 0 || exiting_log="qemu-error" && return 1
}
disk_verify(){
exiting_log="final-image-error"
splb_control="installed"
    if $(sfdisk -d $nocow_dir/$img_file | grep $splb_control >/dev/null) ; then
        return 0
    else 
        return 1
    fi
}
boot_new_arch(){
    start_img="1"
    printf "
            iniciar imagem agora? zero para sim

            será acessível via protocolo spice, em

            localhost:5900%s\n"
        read -s -n1 start_img </dev/tty
        if [ $start_img == "0" ] ; then
     qemu_command="qemu-system-x86_64
                      -enable-kvm
                      -smp 2
                      -m 4096
                      -boot menu=on
                      -cpu host
                      -bios /usr/share/ovmf/x64/OVMF.fd
                      -drive format=raw,file=$nocow_dir/$img_file
                      -vga qxl
                      -spice port=5900,addr=127.0.0.1,disable-ticketing=on"
                      printf "\nimagem iniciada, ctrl-c para desligamento forçado\n"
                      eval ${qemu_command}
                      return 0
        else
            return 0
        fi

}
preserved_setup(){
    boot_new_arch
    boot_instructions
    return 1
}
boot_instructions(){
    printf "
            ######################################################
            #                                                    #
            #                   Stateless Arch                   #
            #                     Generator                      #
            #                                                    #
            ######################################################%s\n

            Use dd para gravar $img_file
            em um dispositivo de bloco, (pendrive ou ssd externo)
            para testá-lo numa máquina física.
            Flags para o dd: bs=4M status=progress oflag=sync

            Para uso desta imagem em máquina virtual,
            importe-o como imagem de disco pura (raw).
            Se solicitado a escolher tipo de barramento,
            selecione sata. Virt-Manager suporta esse tipo de imagem,
            e provavelmente qualquer outro baseado em qemu/kvm.

            Para virtualizadores que não suportam
            imagens desse tipo, consulte a documentação sobre conversão em
            https://qemu.readthedocs.io/en/latest/tools/qemu-img.html
            https://docs.openstack.org/image-guide/convert-images.html
            Vocẽ pode usar o container pod-Arch em modo interativo para a conversão,
            uma vez que qemu-img já está instalado nele.

            Para implantar essa imagem numa máquina física, basta usar o ddrescue,
            fazendo um clone das partições de interesse
            1 e 3 para boot legacy
            2 e 3 para boot efi
            crie as partições de destino com o mesmo número DE BLOCOS da origem,
            mesmas flags GPT, faça o clone, e então expanda
            as partições e os sistemas de arquivos
            -----------------------NESTA ORDEM------------------------------------
            Não grave nas partições envolvidas durante o ddrescue.

            Alternativamente, é possível clonar a partição root
            através das ferramentas do btrfs

                Primeira forma:
                1. crie a partição de destino, já com o tamanho final desejado
                2. btrfs device add /partição/de/destino /
                3. btrfs device remove /partição/de/origem
                4. espere acabar, e tenha energia garantida
                   uma falha aqui destruiria o sistema de arquivos de origem
                5. o sistema será usável na nova implantação imediatamente, sem reinício

                Segunda forma:
                1. crie a partição de destino, já com o tamanho final desejado
                2. formatar como btrfs
                3. btrfs send|receive
                   (tenha energia garantida, mas não deve ser danoso para a origem)
                4. arch-chroot no subvolume @base_system já no disco de destino
                5. instalação da grub, adequada ao modo de boot da máquina,
                   tendo como alvo uma partição da máquina de destino
                6. necessita reinício para usar a nova implantação

                Fazer o clone dessa forma dispensa até o ddrescue das partições
                da grub, como você deve ter imaginado

            O administrador (root) não possui senha.
            Criar uma senha para o root e gerar seu usuário e senha
            podem ser feitos diretamente nas configurações do gnome.

            Sudo está instalado, mas nenhuma política sudoer foi implantada.%s\n" | less

}
exiting_status_print(){
    case $exiting_log in
        deps)
            printf "\n não foi possível baixar dependencias%s\n"
            ;;
        create-disk)
            printf "\n não foi possível criar disco%s\n"
            ;;
        download)
            printf "\n não foi possível baixar os arquivos necessário%s\n"
            ;;
        isohash)
            printf "\no hash da iso está incorreto%s\n"
            ;;
        create-initrd)
            printf "\n não foi gerar o initrd customizado de implantação%s\n"
            ;;
        qemu-user-abort)
            printf "\nexecução do qemu abortada pelo usuário%s\n"
            ;;
        qemu-error)
            printf "\nnão foi possível executar o qemu com sucesso%s\n"
            ;;
        final-image-error)
            printf "\na instalação falhou\nrode o script novamente para outra tentativa%s\n"
            ;;
        preserved)
            printf "\na instalação existente foi preservada%s\n"
            ;;
        *)
            printf "\nerro desconhecido%s\n"
            ;;
    esac
}
##############################---on container end---################################################
##############################---on container end---################################################
##############################---on container end---################################################
##############################---on container end---################################################
##############################---on container end---################################################
##############################---on container end---################################################
##############################---on container end---################################################






#######################################---on vm start---############################################
#######################################---on vm start---############################################
#######################################---on vm start---############################################
#######################################---on vm start---############################################
#######################################---on vm start---############################################
#######################################---on vm start---############################################
entrypoint_vm(){
printf "
        ######################################################
        #                                                    #
        #                   Stateless Arch                   #
        #                     Generator                      #
        #                                                    #
        ######################################################%s\n"

partlabel_dir="/dev/disk/by-partlabel"
label_dir="/dev/disk/by-label"
plb="$partlabel_dir"
lb="$label_dir"
plb_cache="pacmancache"           ### partlabel is gpt flag
splb_cache="validcache"            ### changed if end success pacstrap
plb_efi="grub_efi"
plb_root="ArchLinux"
lb_cache="XFScache"          ### label is filesystem flag
lb_root="StatelessArch"
lb_efi="GRUBEFI"
cache_dir="/var/cache/pacman/pkg"
plb_control="initial"           ### changed if end success arch-chroot
splb_control="installed"
mount_reason="entry"
    build_cache &&
    mount_cache &&
    build_partition_root &&
    build_subvol_root &&
    mount_root &&
    keyring_populate &&
    keyring_update &&
    reflector_populate &&
    run_pacstrap &&
    snapshot_pure_arch &&
    files_on_root &&
    initial_edit_root &&
    exiting_vm || exiting_vm_print_error ; exiting_vm
}
build_cache(){
exit_vm_log="buildcache" &&
    if [ ! -L $plb/$splb_cache ] ; then
        mkfs.xfs $plb/$plb_cache -L $lb_cache -f &&
        sync
    else
        sync
    fi
    return
} 
mount_cache(){
exit_vm_log="mountcache" &&
    if [ -L $plb/$splb_cache ] ; then
        mount $plb/$splb_cache $cache_dir -o noatime
    else
        mount $plb/$plb_cache $cache_dir -o noatime
    fi
    return
}
build_partition_root(){
exit_vm_log="build-part-root" &&
    mkfs.vfat -F32 $plb/$plb_efi -n $lb_efi &&
    sync
    mkfs.btrfs --checksum xxhash $plb/$plb_root -L $lb_root -f &&
    sync
    return
}
build_subvol_root(){
exit_vm_log="build-subvol-root" &&
    mount $plb/$plb_root /mnt &&
       for i in @base_system @sysadmin_state @cache @log @flatpak @home; do
               btrfs su cr /mnt/$i &&
               btrfs filesystem sync /mnt
       done && umount -R /mnt
       return
}
mount_root(){
    if [ $mount_reason == "entry" ] ; then
        exit_vm_log="mount-root"
    elif [ $mount_reason == "pure" ] ; then
        exit_vm_log="pacstrap-save"
    fi &&
    sync &&
    mount $lb/$lb_root /mnt -o compress-force=zstd:1,subvol=@base_system,noatime &&
    mount --mkdir $lb/$lb_efi /mnt/boot/efi
    return
}
keyring_populate(){
##### masked pacman-init
exit_vm_log="keyring-populate" &&
        killall -KILL gpg-agent
        sleep 3 &&
        pacman-key --init &&
        sync &&
        pacman-key --populate &&
        sync
        return
}
keyring_update(){
exit_vm_log="keyring-update" &&
    pacman -Sy archlinux-keyring --noconfirm
    return
}
reflector_populate(){
exit_vm_log="mirrorlist" &&
reflector --save /etc/pacman.d/mirrorlist --country US,Switzerland --latest 50 --sort rate --protocol https
return
}
run_pacstrap(){
exit_vm_log="pacstrap" &&
    sed -i -e "s|#ParallelDownloads.*|ParallelDownloads = 150\nDisableDownloadTimeout\nILoveCandy|g" -e "s|NoProgressBar||g" /etc/pacman.conf
    pacstrap -c /mnt $(cat /root/packagelist.pacman) && sync &&
    sgdisk -c 1:$splb_cache $(grub-probe --target=disk /var/cache/pacman/pkg) && return 0 || return 1
}
snapshot_pure_arch(){
exit_vm_log="pacstrap-save"
    mount_reason="pure"
    umount -Rv /mnt &&
    mount --mkdir $plb/$plb_root /purearch -o 'subvolid='5 &&
    mv /purearch/@base_system /purearch/@pure_pacstrap &&
    sync &&
    execute='btrfs property set -ts /purearch/@pure_pacstrap ro true'
    eval ${execute} && ############### to espace set
    btrfs su snap /purearch/@pure_pacstrap /purearch/@base_system &&
    sync &&
    umount /purearch &&
    mount_root && return 0 || return 1
}
files_on_root(){
exit_vm_log="populate-new-root" &&
    mount --mkdir $lb/$lb_root /tmp/sysadmin_state -o compress-force=zstd:1,subvol=@sysadmin_state,noatime &&
    mkdir -p /tmp/sysadmin_state/etc/pacman.d &&
cat >> /tmp/sysadmin_state/etc/fstab << EOF
$lb/$lb_root    /    btrfs   noatime,compress-force=zstd:1

$lb/$lb_root    /var/lib/flatpak    btrfs   rw,subvol=@flatpak,noatime,compress-force=zstd:1

$lb/$lb_root    /var/cache    btrfs   rw,subvol=@cache,noatime,compress-force=zstd:1

$lb/$lb_root    /var/log    btrfs   rw,subvol=@log,noatime,compress-force=zstd:1

$lb/$lb_root    /home    btrfs   rw,subvol=@home,noatime,compress-force=zstd:1
EOF
    cp /etc/pacman.conf /tmp/sysadmin_state/etc/pacman.conf &&
    cp /etc/pacman.d/mirrorlist /tmp/sysadmin_state/etc/pacman.d/mirrorlist &&
    umount -R /tmp/sysadmin_state/ &&
    cp /etc/shadow /mnt/etc/shadow &&
    tar -xf /root/stateless-arch.tar -C /mnt &&
    cp /root/SA_Generator.sh /usr/local/sbin/pod-Arch-generator &&
    sed "s/^HOOKS=(\(.*\))/HOOKS=(\1 stateless-mode-boot)/" -i /mnt/etc/mkinitcpio.conf &&
    sed "/^#pt_BR./ s/.//" -i /mnt/etc/locale.gen &&
    sed "/^#en_US./ s/.//" -i /mnt/etc/locale.gen &&
cat >> /mnt/usr/local/sbin/pod-Arch-chroot <<EOF
#!/bin/bash
grub-install --target=i386-pc \$(grub-probe --target=disk /) &&
grub-install &&
grub-install --removable &&
grub-mkconfig -o /boot/grub/grub.cfg &&
locale-gen &&
mkinitcpio -P &&
systemctl enable NetworkManager &&
systemctl enable sddm
EOF
    chmod 700 /mnt/usr/local/sbin/pod-Arch-chroot
    return
}
initial_edit_root(){
exit_vm_log="chroot-new-root" &&
    arch-chroot /mnt /usr/local/sbin/pod-Arch-chroot &&
    sgdisk -c 4:$splb_control $(grub-probe --target=disk /mnt) &&
    printf "\n a configuração retorna sucesso%s\n" &&
    return 0 || return 1
}
exiting_vm(){
 printf "
        #####################################################
        #                                                   #
        #           a vm será desligada agora               #
        #           aperte qualquer tecla                   #
        #                                                   #
        #####################################################%s\n"
    read -n1 </dev/tty
    sync &&
    umount -R /mnt
    umount -R $cache_dir
    shutdown now
}
exiting_vm_print_error(){
impossible="não foi possível"
    case $exit_vm_log in
        buildcache)
            printf "\n $impossible criar disco de cache%s\n"
            ;;
        mountcache)
            printf "\n $impossible montar disco de cache%s\n"
            ;;
        build-part-root)
            printf "\n $impossible criar partições de root%s\n"
            ;;
        build-subvol-root)
            printf "\n $impossible criar subvolumes de root%s\n"
            ;;
        mount-root)
            printf "\n $impossible montar partições do root%s\n"
            ;;
        keyring-populate)
            printf "\n $impossible popular o chaveiro do pacman%s\n"
            ;;
        keyring-update)
            printf "\n $impossible atualizar o chaveiro do pacman%s\n"
            ;;
        mirrorlist)
            printf "\n $impossible gerar nova lista de mirrors%s\n"
            ;;
        pacstrap)
            printf "\n $impossible instalar os pacotes requeridos no novo root%s\n"
            ;;
        pacstrap-save)
            printf "\n $impossible criar snapshot pre-configure do novo root%s\n"
            ;;
        populate-new-root)
            printf "\n $impossible criar arquivos de configuração no novo root%s\n"
            ;;
        chroot-new-root)
            printf "\n $impossible executar rotina de configuração no novo root%s\n"
            ;;
        *)
            printf "\n erro desconhecido%s\n"
            ;;
    esac
}
#######################################---on vm end---################################################
#######################################---on vm end---################################################
#######################################---on vm end---################################################
#######################################---on vm end---################################################
#######################################---on vm end---################################################
#######################################---on vm end---################################################





#######################################---entrypoint---################################################
#######################################---entrypoint---################################################
#######################################---entrypoint---################################################
#######################################---entrypoint---################################################
#######################################---entrypoint---################################################
#######################################---entrypoint---################################################

if [ -f /run/.containerenv ] ; then
    on_pod_run
else
printf "
        ######################################################
        #                                                    #
        #                   Stateless Arch                   #
        #                     Generator                      #
        #                                                    #
        ######################################################%s\n"
    grep archisobasedir /proc/cmdline > /dev/null 2>/dev/null && entrypoint_vm || if_exists
fi
