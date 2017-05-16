#!/bin/bash

# Help text
USAGE="\n---------------------------------------------------\nVPC Deploy Script Usage\n---------------------------------------------------\n\n./deploy-vpc.sh -e|--env {ENVIRONMENT} -c|--c {CIDR}\n\n./deploy-vpc.sh -h\n\nEnvironment - dev, test, prod\nCIDR - 18, 19, 20, etc. Ex: If you want a 172.19 VPC, enter 19.\n\n"

if [ "$#" -ne 4 ] ; then
        echo -e "$USAGE"
        exit 3
fi

# Get arguments
while [[ $# -gt 1 ]]
do

key="$1"
case $key in
    -e|--env)
    ENV="$2"
    shift # past argument
    ;;
    -c|--cidr)
    CIDR="$2"
    shift # past argument
    ;;
    *)
    ;;
esac
shift # past argument or value
done

# Get timestamp
DATE=$(date +%s)

# Get environment variables
source ./env/env-$ENV-deploy.list

# Determine keypair
KEY="./scripts/$ENV-key.pem"
echo -e "${PEM}" > $KEY

# Fix key permissions
chmod 600 $KEY

# Replace variables in playbooks to have proper environment name, time, multi AZ option, and VPC CIDR
sed -i -- "6s/.*/    - env: \"$ENV\"/g" "./scripts/playbook-cloudformation.yml"
sed -i -- "6s/.*/    - env: \"$ENV\"/g" "./scripts/playbook-openvpn.yml"
sed -i -- "10s/.*/    - cidr: \"$CIDR\"/g" "./scripts/playbook-openvpn.yml"
sed -i -- "6s/.*/    - env: \"$ENV\"/g" "./scripts/playbook-database.yml"

# Copy Cloudformation JSON and add environment and CIDR
cp ./scripts/vpc.json ./scripts/$ENV-vpc.json
sed -i -- "s/env/$ENV/g" "./scripts/$ENV-vpc.json"
sed -i -- "s/ENV/$(echo $ENV | tr '[:lower:]' '[:upper:]')/g" "./scripts/$ENV-vpc.json"
sed -i -- "s/172.18./172.$CIDR./g" "./scripts/$ENV-vpc.json"

# Set Ansible hosts file location and disable host key checking
export ANSIBLE_HOSTS=./scripts/hosts
export ANSIBLE_HOST_KEY_CHECKING=False

echo ""
echo "************************************ DEPLOYING CLOUDFORMATION TEMPLATE ************************************"
echo ""

# Deploy with Ansible
ansible-playbook ./scripts/playbook-cloudformation.yml

if [ "$?" -ne "0" ]; then
  echo "CloudFormation stack creation failed."
  exit 1
fi

echo ""
echo "************************************ CONFIGURING OPENVPN ************************************"
echo ""

sleep 30

# Install and configure OpenVPN
ansible-playbook ./scripts/playbook-openvpn.yml

if [ "$?" -ne "0" ]; then
  echo "OpenVPN playbook failed."
  exit 1
fi

echo ""
echo "************************************ DEPLOYING DATABASE ************************************"
echo ""

# Deploy database
ansible-playbook ./scripts/playbook-database.yml

if [ "$?" -ne "0" ]; then
  echo "Database playbook failed."
  exit 1
fi

# Delete files
rm ./scripts/$ENV-vpc.json*
yes | rm ./scripts/hosts
rm $KEY
