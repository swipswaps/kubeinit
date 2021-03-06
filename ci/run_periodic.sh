#!/bin/bash
set -e

echo "Executing run.sh"
pip3 install ansible --upgrade

BRANCH_NAME="$1"
PULL_REQUEST="$2"
VARS_YAML_PATH="$3"
DISTRO="$4"
DRIVER="$5"
MASTER="$6"
WORKER="$7"
SCENARIO="$8"

echo "The branch is $BRANCH_NAME"
echo "The pull request is $PULL_REQUEST"
echo "The vars.yaml path is: $VARS_YAML_PATH"
echo "The distro is $DISTRO"
echo "The driver is $DRIVER"
echo "The amount of master nodes is $MASTER"
echo "The amount of worker nodes is $WORKER"
echo "The scenario is $SCENARIO"

# Install and configure ara
# There are problems with multithread ara, we keep the last
# single thread version
python3 -m pip install --upgrade "ara[server]"==1.5.1

# This will nuke the ara database so in each run we have a clean env
rm /root/.ara/server/ansible.sqlite
ara-manage migrate

rm -rf ~/badge_status.svg

export ANSIBLE_CALLBACK_PLUGINS="$(python3 -m ara.setup.callback_plugins)"

# Clone the repo
rm -rf tmp
mkdir -p tmp
cd tmp
git clone https://github.com/kubeinit/kubeinit.git
cd kubeinit

# TODO:Remove when merged
# Keep as an example for cherry-picking workarounds
# git remote add ccamacho https://github.com/ccamacho/kubeinit.git
# git fetch ccamacho
# git cherry-pick 58f718a29d5611234304b1e144a69

# Here we might define some different
# variables depending on the scenario
if [[ "$DISTRO" == "okd" && "$DRIVER" == "libvirt" ]]; then
sudo tee scenario_variables.yml > /dev/null <<EOF
kubeinit_libvirt_test_variable1: example_var
EOF
else
sudo tee scenario_variables.yml > /dev/null <<EOF
kubeinit_libvirt_test_variable2: example_var2
EOF
fi

echo "The content of the scenario_variables.yml file is:"

cat scenario_variables.yml

# By default we deploy 3 master and 1 worker cluster
# the case of 3 master is already by default
# the case of 1 worker is already by default
# We use the .*- expresion to comment the line
# no matter the distro, i.e., okd-master or k8s-master
if [[ "$DISTRO" == "okd.rke" ]]; then
    if [[ "$MASTER" == "1" ]]; then
        sed -i -E "s/.*-master-02/#-master-02/g" ./hosts/okd/inventory
        sed -i -E "s/.*-master-02/#-master-02/g" ./hosts/rke/inventory
        sed -i -E "s/.*-master-02/#-master-02/g" ./hosts/k8s/inventory
        sed -i -E "s/.*-master-02/#-master-02/g" ./hosts/cdk/inventory
        sed -i -E "s/.*-master-02/#-master-02/g" ./hosts/eks/inventory

        sed -i -E "s/.*-master-03/#-master-03/g" ./hosts/okd/inventory
        sed -i -E "s/.*-master-03/#-master-03/g" ./hosts/rke/inventory
        sed -i -E "s/.*-master-03/#-master-03/g" ./hosts/k8s/inventory
        sed -i -E "s/.*-master-03/#-master-03/g" ./hosts/cdk/inventory
        sed -i -E "s/.*-master-03/#-master-02/g" ./hosts/eks/inventory
    fi

    if [[ "$WORKER" == "0" ]]; then
        sed -i -E "s/.*-worker-01/#-worker-01/g" ./hosts/okd/inventory
        sed -i -E "s/.*-worker-01/#-worker-01/g" ./hosts/rke/inventory
        sed -i -E "s/.*-worker-01/#-worker-01/g" ./hosts/k8s/inventory
        sed -i -E "s/.*-worker-01/#-worker-01/g" ./hosts/cdk/inventory
        sed -i -E "s/.*-worker-01/#-worker-01/g" ./hosts/eks/inventory
    fi

    if [[ "$WORKER" == "2" ]]; then
        sed -i -E "/# .*-worker-02/ s/# //g" ./hosts/okd/inventory
        sed -i -E "/# .*-worker-02/ s/# //g" ./hosts/rke/inventory
        sed -i -E "/# .*-worker-02/ s/# //g" ./hosts/k8s/inventory
        sed -i -E "/# .*-worker-02/ s/# //g" ./hosts/cdk/inventory
        sed -i -E "/# .*-worker-02/ s/# //g" ./hosts/eks/inventory
    fi
else
    if [[ "$MASTER" == "1" ]]; then
        sed -i -E "s/.*-master-02/#-master-02/g" ./hosts/$DISTRO/inventory
        sed -i -E "s/.*-master-03/#-master-03/g" ./hosts/$DISTRO/inventory
    fi

    if [[ "$WORKER" == "0" ]]; then
        sed -i -E "s/.*-worker-01/#-worker-01/g" ./hosts/$DISTRO/inventory
    fi

    if [[ "$WORKER" == "2" ]]; then
        sed -i -E "/# .*-worker-02/ s/# //g" ./hosts/$DISTRO/inventory
    fi
fi
# We need to remove any created VM in other jobs
# TODO: Add cleanup tasks

for i in $(virsh -q list | awk '{ print $2 }'); do
    virsh destroy $i;
    virsh undefine $i --remove-all-storage;
done;
for i in $(virsh -q net-list | awk '{ print $1 }'); do
    virsh net-destroy $i;
    virsh net-undefine $i;
done;


ansible-playbook \
    --user root \
    -v -i ./hosts/$DISTRO/inventory \
    --become \
    --become-user root \
    -e @scenario_variables.yml \
    ./playbooks/$DISTRO.yml
