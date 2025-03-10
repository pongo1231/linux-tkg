#!/bin/bash

# Stop the script at any ecountered error
set -e

_where=`pwd`
srcdir="$_where"

source customization.cfg

source linux-tkg-config/prepare

msg2() {
 echo -e " \033[1;34m->\033[1;0m \033[1;1m$1\033[1;0m" >&2
}

error() {
 echo -e " \033[1;31m==> ERROR: $1\033[1;0m" >&2
}

warning() {
 echo -e " \033[1;33m==> WARNING: $1\033[1;0m" >&2
}

plain() {
 echo -e "$1" >&2
}

_distro_prompt() {
  echo "Which linux distribution are you running ?"
  echo "if it's not on the list, chose the closest one to it: Fedora/Suse for RPM, Ubuntu/Debian for DEB"
  _prompt_from_array "Debian" "Fedora" "Suse" "Ubuntu" "Gentoo" "Generic"
  _distro="${_selected_value}"
}

_install_dependencies() {
  if [ "$_compiler_name" = "llvm" ]; then
    clang_deps="llvm clang lld"
  fi
  if [ "$_distro" = "Debian" -o "$_distro" = "Ubuntu" ]; then
    msg2 "Installing dependencies"
    sudo apt install git wget build-essential schedtool fakeroot libncurses5-dev libssl-dev ccache bison flex qtbase5-dev bc rsync kmod cpio libelf-dev lz4 zstd ${clang_deps} -y
  elif [ "$_distro" = "Fedora" ]; then
    msg2 "Installing dependencies"
    if [ $(rpm -E %fedora) = "32" ]; then
      sudo dnf install fedpkg fedora-packager rpmdevtools ncurses-devel pesign grubby qt5-devel libXi-devel gcc-c++ git ccache flex bison elfutils-libelf-devel openssl-devel dwarves rpm-build lz4 zstd ${clang_deps} -y
    else
      sudo dnf install qt5-qtbase-devel fedpkg fedora-packager rpmdevtools ncurses-devel pesign grubby libXi-devel gcc-c++ git ccache flex bison elfutils-libelf-devel elfutils-devel openssl openssl-devel dwarves rpm-build perl-devel perl-generators python3-devel make lz4 zstd -y ${clang_deps} -y
    fi
  elif [ "$_distro" = "Suse" ]; then
    msg2 "Installing dependencies"
    sudo zypper install -y rpmdevtools ncurses-devel pesign libXi-devel gcc-c++ git ccache flex bison elfutils libelf-devel openssl-devel dwarves make patch bc rpm-build libqt5-qtbase-common-devel libqt5-qtbase-devel lz4 ${clang_deps}
  fi
}

_linux_git_branch_checkout() {

  cd "$_where"

  if [[ -z $_git_mirror || ! $_git_mirror =~ ^(kernel\.org|googlesource\.com)$ ]]; then
    while true; do
      echo "Which git repository would you like to clone the linux sources from ?"
      echo "   0) kernel.org (official)"
      echo "   1) googlesource.com (faster mirror)"
      read -p "[0-1]: " _git_repo_index

      if [ "$_git_repo_index" = "0" ]; then
        _git_mirror="kernel.org"
        break
      elif [ "$_git_repo_index" = "1" ]; then
        _git_mirror="googlesource.com"
        break
      else
        echo "Wrong index."
      fi
    done
  fi

  if ! [ -d linux-src-git ]; then
    msg2 "First initialization of the linux source code git folder"
    mkdir linux-src-git
    cd linux-src-git
    git init

    git remote add kernel.org https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
    git remote add googlesource.com https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable
  else
    cd linux-src-git

    # Remove "origin" remote if present
    if git remote -v | grep -w "origin" ; then
      git remote rm origin
    fi

    if ! git remote -v | grep -w "kernel.org" ; then
      git remote add kernel.org https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
    fi
    if ! git remote -v | grep -w "googlesource.com" ; then
      git remote add googlesource.com https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable
    fi

    msg2 "Current branch: $(git branch | grep "\*")"
    msg2 "Reseting files to their original state"

    git reset --hard HEAD
    git clean -f -d -x
  fi

  if [[ "$_sub" = rc* ]]; then
    msg2 "Switching to master branch for RC Kernel"

    if ! git branch --list | grep "master-${_git_mirror}" ; then
      msg2 "master branch doesn't locally exist, shallow cloning..."
      git remote set-branches --add kernel.org master
      git remote set-branches --add googlesource.com master
      git fetch --depth=1 $_git_mirror master
      git fetch --depth 1 $_git_mirror tag "v${_basekernel}-${_sub}"
      git checkout -b master-${_git_mirror} ${_git_mirror}/master
    else
      msg2 "master branch exists locally, updating..."
      git checkout master-${_git_mirror}
      git fetch --depth 1 $_git_mirror tag "v${_basekernel}-${_sub}"
      git reset --hard ${_git_mirror}/master
    fi
    msg2 "Checking out latest RC tag: v${_basekernel}-${_sub}"
    git checkout "v${_basekernel}-${_sub}"
  else
    # define kernel tag so we treat the 0 subver properly
    _kernel_tag="v${_basekernel}.${_sub}"
    if [ "$_sub" = "0" ];then
      _kernel_tag="v${_basekernel}"
    fi

    msg2 "Switching to linux-${_basekernel}.y"
    if ! git branch --list | grep -w "linux-${_basekernel}-${_git_mirror}" ; then
      msg2 "${_basekernel}.y branch doesn't locally exist, shallow cloning..."
      git remote set-branches --add kernel.org linux-${_basekernel}.y
      git remote set-branches --add googlesource.com linux-${_basekernel}.y
      git fetch --depth=1 $_git_mirror linux-${_basekernel}.y
      git fetch --depth=1 $_git_mirror tag "${_kernel_tag}"
      git checkout -b linux-${_basekernel}-${_git_mirror} ${_git_mirror}/linux-${_basekernel}.y
    else
      msg2 "${_basekernel}.y branch exists locally, updating..."
      git checkout linux-${_basekernel}-${_git_mirror}
      git fetch --depth 1 $_git_mirror tag "${_kernel_tag}"
      git reset --hard ${_git_mirror}/linux-${_basekernel}.y
    fi
    msg2 "Checking out latest release: ${_kernel_tag}"
    git checkout "${_kernel_tag}"
  fi
}

if [ "$1" != "install" ] && [ "$1" != "config" ] && [ "$1" != "uninstall-help" ]; then
  msg2 "Argument not recognised, options are:
        - config : interactive script that shallow clones the linux 5.x.y git tree into the folder linux-src-git, then applies extra patches and prepares the .config file
                   by copying the one from the currently running linux system and updates it.
        - install : does the config step, proceeds to compile, then prompts to install
                    - 'DEB' distros: it creates .deb packages that will be installed then stored in the DEBS folder.
                    - 'RPM' distros: it creates .rpm packages that will be installed then stored in the RPMS folder.
                    - 'Generic' distro: it uses 'make modules_install' and 'make install', uses 'dracut' to create an initramfs, then updates grub's boot entry.
        - uninstall-help : [RPM and DEB based distros only], lists the installed kernels in this system, then gives hints on how to uninstall them manually."
  exit 0
fi

# Load external configuration file if present. Available variable values will overwrite customization.cfg ones.
if [ -e "$_EXT_CONFIG_PATH" ]; then
  msg2 "External configuration file $_EXT_CONFIG_PATH will be used and will override customization.cfg values."
  source "$_EXT_CONFIG_PATH"
fi

if [ "$1" = "install" ] || [ "$1" = "config" ]; then

  if [ -z $_distro ] && [ "$1" = "install" ]; then
    _distro_prompt
  fi

  if [ "$1" = "config" ]; then
    _distro="Unknown"
  fi

  # Run init script that is also run in PKGBUILD, it will define some env vars that we will use
  _tkg_initscript

  if [[ "${_compiler}" = "llvm" && "${_distro}" =~ ^(Generic|Gentoo)$ ]]; then
    read -p "Replace \"libunwind\" with \"llvm-libunwind\" ? Y/[n]:" _libunwind_replace
    if [[ "${_libunwind_replace}" =~ ^(y|yes|Yes|Y)$ ]]; then
      export LDFLAGS_MODULE="-unwindlib=libunwind"
      export HOSTLDFLAGS="-unwindlib=libunwind"
    fi
  fi

  if [[ $1 = "install" && ! "$_distro" =~ ^(Ubuntu|Debian|Fedora|Suse|Gentoo|Generic)$ ]]; then
    msg2 "Variable \"_distro\" in \"customization.cfg\" has been set to an unkown value. Prompting..."
    _distro_prompt
  fi

  # Install the needed dependencies if the user wants to install the kernel
  # Not needed if the user asks for install.sh config
  if [ $1 == "install" ]; then
    _install_dependencies
  fi

  # Force prepare script to avoid Arch specific commands if the user is using `config`
  if [ "$1" = "config" ]; then
    _distro=""
  fi

  # Git clone (if necessary) and checkout the asked branch by the user
  _linux_git_branch_checkout

  cd "$_where"

  case "$_basever" in
    "57")
    opt_ver="5.7"
    opt_alternative_url="true"
    ;;
    "58")
    opt_ver="5.8-5.14"
    ;;
    "59")
    opt_ver="5.8-5.14"
    ;;
    "510")
    opt_ver="5.8-5.14"
    ;;
    "511")
    opt_ver="5.8-5.14"
    ;;
    "512")
    opt_ver="5.8-5.14"
    ;;
    "513")
    opt_ver="5.8-5.14"
    ;;
    "514")
    opt_ver="5.8-5.14"
    ;;
    "515")
    opt_ver="5.15+"
    ;;
  esac

  if [ -n "$opt_ver" ]; then
    msg2 "Downloading Graysky2's CPU optimisations patch"
    if [ "$opt_alternative_url" != "true" ]; then
      wget "https://raw.githubusercontent.com/graysky2/kernel_compiler_patch/master/more-uarches-for-kernel-${opt_ver}.patch"
    else
      wget "https://raw.githubusercontent.com/graysky2/kernel_compiler_patch/master/outdated_versions/enable_additional_cpu_optimizations_for_gcc_v10.1+_kernel_v${opt_ver}.patch"
    fi
  fi

  # cd into the linux-src folder is important before calling _tkg_srcprep
  cd "$_where/linux-src-git"
  _tkg_srcprep

  _build_dir="$_where"
  if [ "$_use_tmpfs" = "true" ]; then
    if [ -d "$_tmpfs_path/linux-tkg" ]; then
      msg2 "Nuking linux-tkg tmpfs folder $_tmpfs_path/linux-tkg"
      rm -rf "$_tmpfs_path/linux-tkg"
    fi
    mkdir "$_tmpfs_path/linux-tkg"
    cp -r "$_where/linux-src-git" "$_tmpfs_path/linux-tkg/linux-src-git"

    # cd into the linux-src folder is important before calling _tkg_srcprep
    _build_dir="$_tmpfs_path/linux-tkg"
    cd "$_tmpfs_path/linux-tkg/linux-src-git"
  fi


  # Uppercase characters are not allowed in source package name for debian based distros
  if [ "$_distro" = "Debian" ] || [ "$_distro" = "Ubuntu" ] && [ "$_cpusched" = "MuQSS" ]; then
    _cpusched="muqss"
  fi

  msg2 "Configuration done."
fi

if [ "$1" = "install" ]; then

  if [ -e "${_where}/winesync.rules" ]; then
    msg2 "Installing udev rule for winesync"
    sudo cp "${_where}"/winesync.rules /etc/udev/rules.d/winesync.rules
    sudo chmod 644 /etc/udev/rules.d/winesync.rules

    msg2 "Adding winesync to '/etc/modules-load.d' for auto-loading by systemd - Password prompt incoming!"
    sudo sh -c 'echo "winesync" >/etc/modules-load.d/winesync.conf'
  fi

  # Use custom compiler paths if defined
  if [ "$_compiler_name" = "-llvm" ] && [ -n "${CUSTOM_LLVM_PATH}" ]; then
    PATH="${CUSTOM_LLVM_PATH}/bin:${CUSTOM_LLVM_PATH}/lib:${CUSTOM_LLVM_PATH}/include:${PATH}"
  elif [ -n "${CUSTOM_GCC_PATH}" ]; then
    PATH="${CUSTOM_GCC_PATH}/bin:${CUSTOM_GCC_PATH}/lib:${CUSTOM_GCC_PATH}/include:${PATH}"
  fi

  if [ "$_force_all_threads" = "true" ]; then
    _thread_num=`nproc`
  else
    _thread_num=`expr \`nproc\` / 4`
    if [ "$_thread_num" = "0" ]; then
      _thread_num=1
    fi
  fi

  # ccache
  if [ "$_noccache" != "true" ]; then
    export PATH="/usr/lib64/ccache/:/usr/lib/ccache/bin/:$PATH"

    export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
    export CCACHE_NOHASHDIR="true"
    msg2 'Enabled ccache'
  fi

  if [ -z $_kernel_localversion ]; then
    _kernel_flavor="tkg-${_cpusched}${_compiler_name}"
  else
    _kernel_flavor="tkg-${_kernel_localversion}"
  fi

  # Setup kernel_subver variable
  if [[ "$_sub" = rc* ]]; then
    # if an RC version, subver will always be 0
    _kernel_subver=0
  else
    _kernel_subver="${_sub}"
  fi

  _timed_build() {
    _runtime=$( time ( schedtool -B -n 1 -e ionice -n 1 "$@" 2>&1 ) 3>&1 1>&2 2>&3 ) || _runtime=$( time ( "$@" 2>&1 ) 3>&1 1>&2 2>&3 )
  }

  if [ "$_distro" = "Ubuntu" ]  || [ "$_distro" = "Debian" ]; then

    msg2 "Building kernel DEB packages"
    _timed_build make ${llvm_opt} -j ${_thread_num} deb-pkg LOCALVERSION=-${_kernel_flavor}
    msg2 "Building successfully finished!"

    # Create DEBS folder if it doesn't exist
    cd "$_where"
    mkdir -p DEBS

    # Move deb files to DEBS folder inside the linux-tkg folder
    mv "$_build_dir"/*.deb "$_where"/DEBS/

    read -p "Do you want to install the new Kernel ? Y/[n]: " _install
    if [[ $_install =~ [yY] ]] || [ $_install = "yes" ] || [ $_install = "Yes" ]; then
      cd "$_where"
      if [[ "$_sub" = rc* ]]; then
        _kernelname=$_basekernel.$_kernel_subver-$_sub-$_kernel_flavor
      else
        _kernelname=$_basekernel.$_kernel_subver-$_kernel_flavor
      fi
      _headers_deb="linux-headers-${_kernelname}*.deb"
      _image_deb="linux-image-${_kernelname}_*.deb"
      _kernel_devel_deb="linux-libc-dev_${_kernelname}*.deb"

      cd DEBS
      sudo dpkg -i $_headers_deb $_image_deb $_kernel_devel_deb
    fi

  elif [[ "$_distro" = "Fedora" ||  "$_distro" = "Suse" ]]; then

    # Replace dashes with underscores, it seems that it's being done by binrpm-pkg
    # Se we can actually refer properly to the rpm files.
    _kernel_flavor=${_kernel_flavor//-/_}

    if [[ "$_sub" = rc* ]]; then
      _extra_ver_str="_${_sub}_${_kernel_flavor}"
    else
      _extra_ver_str="_${_kernel_flavor}"
    fi

    _fedora_work_dir="${HOME}/.cache/linux-tkg-rpmbuild"
    if [ "$_use_tmpfs" = "true" ]; then
      _fedora_work_dir="$_tmpfs_path/linux-tkg/linux-tkg-rpmbuild"
    fi

    msg2 "Building kernel RPM packages"
    RPMOPTS="--define '_topdir ${_fedora_work_dir}'" _timed_build make ${llvm_opt} -j ${_thread_num} rpm-pkg EXTRAVERSION="${_extra_ver_str}"
    msg2 "Building successfully finished!"

    # Create RPMS folder if it doesn't exist
    cd "$_where"
    mkdir -p RPMS

    # Move rpm files to RPMS folder inside the linux-tkg folder
    mv ${_fedora_work_dir}/RPMS/x86_64/*tkg* "$_where"/RPMS/

    read -p "Do you want to install the new Kernel ? Y/[n]: " _install
    if [[ "$_install" =~ ^(Y|y|Yes|yes)$ ]]; then

      if [[ "$_sub" = rc* ]]; then
        _kernelname=$_basekernel.${_kernel_subver}_${_sub}_$_kernel_flavor
      else
        _kernelname=$_basekernel.${_kernel_subver}_$_kernel_flavor
      fi
      _headers_rpm="kernel-headers-${_kernelname}*.rpm"
      _kernel_rpm="kernel-${_kernelname}*.rpm"
      # The headers are actually contained in the kernel-devel RPM and not the headers one...
      _kernel_devel_rpm="kernel-devel-${_kernelname}*.rpm"

      cd RPMS
      if [ "$_distro" = "Fedora" ]; then
        sudo dnf install $_headers_rpm $_kernel_rpm $_kernel_devel_rpm
      elif [ "$_distro" = "Suse" ]; then
        msg2 "Some files from 'linux-glibc-devel' will be replaced by files from the custom kernel-hearders package"
        msg2 "To revert back to the original kernel headers do 'sudo zypper install -f linux-glibc-devel'"
        sudo zypper install --replacefiles --allow-unsigned-rpm $_headers_rpm $_kernel_rpm $_kernel_devel_rpm
      fi

      msg2 "Install successful"
    fi

  elif [[ "$_distro" =~ ^(Gentoo|Generic)$ ]]; then

    ./scripts/config --set-str LOCALVERSION "-${_kernel_flavor}"

    if [[ "$_sub" = rc* ]]; then
      _kernelname=$_basekernel.${_kernel_subver}-${_sub}-$_kernel_flavor
    else
      _kernelname=$_basekernel.${_kernel_subver}-$_kernel_flavor
    fi

    msg2 "Building kernel"
    _timed_build make ${llvm_opt} -j ${_thread_num}
    msg2 "Build successful"

    if [ "$_STRIP" = "true" ]; then
      echo "Stripping vmlinux..."
      strip -v $STRIP_STATIC "vmlinux"
    fi

    _headers_folder_name="linux-$_kernelname"

    msg2 "Removing unneeded architectures..."
    for arch in arch/*/; do
      [[ $arch = */x86/ ]] && continue
      echo "Removing $(basename "$arch")"
      rm -r "$arch"
    done

    msg2 "Removing broken symlinks..."
    find -L . -type l -printf 'Removing %P\n' -delete

    msg2 "Removing loose objects..."
    find . -type f -name '*.o' -printf 'Removing %P\n' -delete

    msg2 "Stripping build tools..."
    while read -rd '' file; do
      case "$(file -bi "$file")" in
        application/x-sharedlib\;*)      # Libraries (.so)
          strip -v $STRIP_SHARED "$file" ;;
        application/x-archive\;*)        # Libraries (.a)
          strip -v $STRIP_STATIC "$file" ;;
        application/x-executable\;*)     # Binaries
          strip -v $STRIP_BINARIES "$file" ;;
        application/x-pie-executable\;*) # Relocatable binaries
          strip -v $STRIP_SHARED "$file" ;;
      esac
    done < <(find . -type f -perm -u+x ! -name vmlinux -print0)

    echo -e "\n\n"

    msg2 "The installation process will run the following commands:"
    echo "    # copy the patched and compiled sources to /usr/src/$_headers_folder_name"
    echo "    sudo make modules_install"
    echo "    sudo make install"
    echo "    sudo dracut --force --hostonly ${_dracut_options} --kver $_kernelname"
    echo "    sudo grub-mkconfig -o /boot/grub/grub.cfg"

    msg2 "Note: Uninstalling requires manual intervention, use './install.sh uninstall-help' for more information."
    read -p "Continue ? Y/[n]: " _continue

    if ! [[ $_continue =~ ^(Y|y|Yes|yes)$ ]];then
      exit 0
    fi

    msg2 "Copying files over to /usr/src/$_headers_folder_name"
    if [ -d "/usr/src/$_headers_folder_name" ]; then
      msg2 "Removing old folder in /usr/src/$_headers_folder_name"
      sudo rm -rf "/usr/src/$_headers_folder_name"
    fi
    sudo cp -R . "/usr/src/$_headers_folder_name"
    sudo rm -rf "/usr/src/$_headers_folder_name/.git"
    cd "/usr/src/$_headers_folder_name"

    msg2 "Installing modules"
    if [ "$_STRIP" = "true" ]; then
      sudo make modules_install INSTALL_MOD_STRIP="1"
    else
      sudo make modules_install
    fi
    msg2 "Removing modules from source folder in /usr/src/${_kernel_src_gentoo}"
    sudo find . -type f -name '*.ko' -delete
    sudo find . -type f -name '*.ko.cmd' -delete

    msg2 "Installing kernel"
    sudo make install
    msg2 "Creating initramfs"
    sudo dracut --force --hostonly ${_dracut_options} --kver $_kernelname
    msg2 "Updating GRUB"
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    if [ "$_distro" = "Gentoo" ]; then

      msg2 "Selecting the kernel source code as default source folder"
      sudo ln -sfn "/usr/src/$_headers_folder_name" "/usr/src/linux"

      msg2 "Rebuild kernel modules with \"emerge @module-rebuild\" ?"
      if [ "$_compiler" = "llvm" ];then
        warning "Building modules with LLVM/Clang is mostly unsupported OOTB by \"emerge @module-rebuild\" except for Nvidia 465.31+"
        warning "     Manually setting \"CC=clang\" for some modules may work if you haven't used LTO"
      fi

      read -p "Y/[n]: " _continue
      if [[ $_continue =~ ^(Y|y|Yes|yes)$ ]];then
        sudo emerge @module-rebuild --keep-going
      fi

    fi

  fi
fi

if [ "$1" = "uninstall-help" ]; then

  if [ -z $_distro ]; then
    _distro_prompt
  fi

  cd "$_where"

  if [ "$_distro" = "Ubuntu" ]; then
    msg2 "List of installed custom tkg kernels: "
    dpkg -l "*tkg*" | grep "linux.*tkg"
    dpkg -l "*linux-libc-dev*" | grep "linux.*tkg"
    msg2 "To uninstall a version, you should remove the linux-image, linux-headers and linux-libc-dev associated to it (if installed), with: "
    msg2 "      sudo apt remove linux-image-VERSION linux-headers-VERSION linux-libc-dev-VERSION"
    msg2 "       where VERSION is displayed in the lists above, uninstall only versions that have \"tkg\" in its name"
    msg2 "Note: linux-libc-dev packages are no longer created and installed, you can safely remove any remnants."
  elif [ "$_distro" = "Fedora" ]; then
    msg2 "List of installed custom tkg kernels: "
    dnf list --installed kernel*
    msg2 "To uninstall a version, you should remove the kernel, kernel-headers and kernel-devel associated to it (if installed), with: "
    msg2 "      sudo dnf remove --noautoremove kernel-VERSION kernel-devel-VERSION kernel-headers-VERSION"
    msg2 "       where VERSION is displayed in the second column"
    msg2 "Note: kernel-headers packages are no longer created and installed, you can safely remove any remnants."
  elif [ "$_distro" = "Suse" ]; then
    msg2 "List of installed custom tkg kernels: "
    zypper packages --installed-only | grep "kernel.*tkg"
    msg2 "To uninstall a version, you should remove the kernel, kernel-headers and kernel-devel associated to it (if installed), with: "
    msg2 "      sudo zypper remove --no-clean-deps kernel-VERSION kernel-devel-VERSION kernel-headers-VERSION"
    msg2 "       where VERSION is displayed in the second to last column"
    msg2 "Note: kernel-headers packages are no longer created and installed, you can safely remove any remnants."
  elif [[ "$_distro" =~ ^(Generic|Gentoo)$ ]]; then
    msg2 "Folders in /lib/modules :"
    ls /lib/modules
    msg2 "Files in /boot :"
    ls /boot
    msg2 "To uninstall a kernel version installed through install.sh with 'Generic' as a distro:"
    msg2 "  - Remove manually the corresponding folder in '/lib/modules'"
    msg2 "  - Remove manually the corresponding 'System.map', 'vmlinuz', 'config' and 'initramfs' in the folder :/boot"
    msg2 "  - Update the boot menu. e.g. 'sudo grub-mkconfig -o /boot/grub/grub.cfg'"
  fi

fi
