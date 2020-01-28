#! /bin/bash

# Patch amazon-eks-gpu-node-* AMI to work around stdin issue:
#  docker run -i ... # *without* -t
# closes stdin inside the container and this impacts any streaming into it where
# stdin needs to operate in binary mode rather than terminal mode, e.g. file
# transfer, such as kubectl cp.

# How to illustrate the issue:
#  echo "loopback from stdin" | sudo docker run --rm -i busybox cat
#
# Expected output: loopback from stdin
# Actual output: none because the container's stdin is closed.

check_stdin_stream() {
    local test_string="loopback from stdin"
    output=$(set -x; echo "$test_string" | sudo docker run --rm -i busybox cat)
    if [[ "$output" == "$test_string" ]]; then
        echo "output=\`$output'"
        return 0
    else
        echo >&2 "Expected: \`$test_string', Found: \`$output'"
        return 1
    fi
}


# Verify GPU availability inside the container:
check_gpu() {
    local run_args
    for run_args in "" "--gpus all" "--runtime nvidia"; do
        (set -x; sudo docker run $run_args --rm nvidia/cuda:9.0-base nvidia-smi) || return 1
    done
    return 0
}


# Is the patch required?
if check_stdin_stream; then
    echo "The patch is not required"
    exit 0
fi

set -e

# Pre-requisites:
(set -x; sudo yum install -y yum-utils rsync)

# Backup original yum config, unless already done so. It will be restored at the
# end.
yum_backup_dir=/tmp/yum_backup
yum_backup_done="$yum_backup_dir/done"
sudo mkdir -p $yum_backup_dir
if [[ ! -f "$yum_backup_done" ]]; then
    (
        set -x
        sudo rsync -aHogvS /etc/yum* $yum_backup_dir/etc && \
            sudo touch "$yum_backup_done"
    )
fi

# Stop and remove current docker and nvidia support:
(
    set -x
    sudo systemctl stop docker
    sudo systemctl disable docker
    sudo yum remove -y 'docker*' '*nvidia-container*'
)

# Re-install a newer docker and nvidia support from non Amazon repos.
(set -x; sudo yum-config-manager --disable 'amzn2*' '*nvidia*')

# Enable CentOS 7 repo and install docker's requirement container-selinux from
# it:
installroot=/tmp/centos
if [[ ! -f $installroot/etc/yum.repos.d/CentOS-Base.repo ]]; then
    (
        set -x
        sudo yum install -y \
             --installroot=$installroot \
             http://mirror.centos.org/centos/7/os/x86_64/Packages/centos-release-7-7.1908.0.el7.centos.x86_64.rpm
    )
fi
(
    set -x
    sudo cp -p $installroot/etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo
    sudo sed -i -e 's/\$releasever/7/g' /etc/yum.repos.d/CentOS-Base.repo
    sudo rsync -aHogS $installroot/etc/pki/rpm-gpg/ /etc/pki/rpm-gpg
    sudo rsync -aHogS $installroot/etc/yum/vars/ /etc/yum/vars
    sudo yum-config-manager --enable 'CentOS*'
    sudo yum clean metadata

    sudo yum install -y \
         device-mapper-persistent-data \
         lvm2 \
         container-selinux

    # Latest docker:
    sudo yum-config-manager \
         --add-repo \
         https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum-config-manager --enable 'docker*'
    sudo yum install -y docker-ce
)

# Reinstall the latest nvidia-docker2; ideally nvidia-container-toolkit should
# be used but k8s is not ready for it.
distribution=$(. $installroot/etc/os-release;echo $ID$VERSION_ID)
(
    set -x
    sudo yum-config-manager \
         --add-repo \
         https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo
    sudo yum-config-manager \
         --save \
         --setopt=nvidia-docker.repo_gpgcheck=false \
         --setopt=libnvidia-container.repo_gpgcheck=false \
         --setopt=nvidia-container-runtime.repo_gpgcheck=false
    sudo yum --enablerepo=libnvidia-container clean metadata
    sudo yum install -y nvidia-docker2 # nvidia-container-toolkit doesn't work w/ k8s
    sudo systemctl enable docker
    sudo systemctl restart docker
)

# Test:
check_gpu && check_stdin_stream

# Restore yum conf:
if [[ -f "$yum_backup_done" ]]; then
    (
        set -x
        sudo rsync -aHogvS --delete \
             $yum_backup_dir/etc/yum/ /etc/yum
        sudo rsync -aHogvS --delete \
             $yum_backup_dir/etc/yum.repos.d/ /etc/yum.repos.d
        sudo yum clean metadata
    )
fi
yum repolist

# Verify that future updates will not break anything:
(set -x; sudo yum update -y --skip-broken)

# Test that it works after restart:
(set -x; sudo systemctl restart docker)
check_gpu && check_stdin_stream

