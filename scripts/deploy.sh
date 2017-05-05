#!/bin/bash

# Help text
USAGE="\n---------------------------------------------------\nDeploy Script Usage\n---------------------------------------------------\n\n./deploy.sh -e|--env {ENVIRONMENT} -l|--location {LOCATION} -b|--build {BUILD} -t|--tag {COMMIT_TAG}\n\n./deploy.sh -h\n\nEnvironment - dev\nLocation - local, circleci\nBuild - web, api\nTag - tag from Git commit\n\n"

if [ "$#" -ne 8 ] ; then
        echo -e "$USAGE"
        exit 3
fi

# Possible location, and environment values
ENVS=("dev","test","prod")
LOCATIONS=("mac","linux")
BUILDS=("api","web")

# Get arguments
while [[ $# -gt 1 ]]
do

key="$1"
case $key in
    -e|--env)
    ENV="$2"
    # Check if environment is valid, exit if invalid
    if [[ ! ${ENVS[*]} =~ "$ENV" ]]; then
      echo "Invalid environment. Valid options are dev, test, or prod."
      exit 1
    fi
    shift # past argument
    ;;
    -l|--location)
    LOCATION="$2"
    # Check for build location
    if [[ ! ${LOCATIONS[*]} =~ "$LOCATION" ]]; then
      echo "Invalid build location. Valid options are linux or mac."
      exit 1
    fi
    shift # past argument
    ;;
    -b|--build)
    BUILD="$2"
    # Check if build is valid, exit if invalid
    if [[ ! ${BUILDS[*]} =~ "$BUILD" ]]; then
      echo "Invalid build type. Valid options are api or web."
      exit 1
    fi
    shift # past argument
    ;;
    -t|--tag)
    TAG="$2"
    shift # past argument
    ;;
    *)
    ;;
esac
shift # past argument or value
done

# Get environment variables
source ./env/env-$ENV-deploy.list

# Determine keypair
KEY="./scripts/$ENV-key.pem"

if [ $ENV = "dev" ]; then
  echo -e "${DEV_PEM}" > $KEY
elif [ $ENV = "test" ]; then
  echo -e "${TEST_PEM}" > $KEY
elif [ $ENV = "prod" ]; then
  echo -e "${PROD_PEM}" > $KEY
fi

# Fix key permissions
chmod 600 $KEY

# Get timestamp
DATE=$(date +%s)

# Get port
if [ $BUILD = "api" ]; then
  PORT=9000
elif [ $BUILD = "web" ]; then
  PORT=8080
fi

# Replace variables in playbook.yml with new environment, build, timestamp, port, tag, and number of instances
sed -i -- "7s/.*/    - \"build\": \"$BUILD\"/g" "./scripts/playbook.yml"
sed -i -- "8s/.*/    - \"env\": \"$ENV\"/g" "./scripts/playbook.yml"
sed -i -- "9s/.*/    - \"timestamp\": \"$DATE\"/g" "./scripts/playbook.yml"
sed -i -- "10s/.*/    - \"port\": \"$PORT\"/g" "./scripts/playbook.yml"
sed -i -- "11s/.*/    - \"tag\": \"$TAG\"/g" "./scripts/playbook.yml"
sed -i -- "12s/.*/    - \"aws_account\": \"$AWS_ACCOUNT\"/g" "./scripts/playbook.yml"

# Configure Packer
PACKER="./scripts/packer.json"
sed -i -- "5s/.*/		\"env\": \"$ENV\",/g" $PACKER
sed -i -- "6s/.*/		\"build\": \"$BUILD\",/g" $PACKER
sed -i -- "7s/.*/    \"timestamp\": \"$DATE\",/g" $PACKER
sed -i -- "8s/.*/    \"tag\": \"$TAG\",/g" $PACKER

if [ $BUILD = "api" ]; then
  sed -i -- "35s/.*/				\"API\": \"{{user \`tag\`}}\"/g" $PACKER
elif [ $BUILD = "web" ]; then
  sed -i -- "35s/.*/				\"Web\": \"{{user \`tag\`}}\"/g" $PACKER
fi

# Build new AMI with Packer
if [ $LOCATION = "mac" ]; then
  ./scripts/bin/packer-mac build $PACKER
elif [ $LOCATION = "linux" ]; then
  ./scripts/bin/packer build $PACKER
fi

if [ "$?" -ne "0" ]; then
  echo "Packer AMI creation failed."
  exit 1
fi

# Wait for AMI to actually become available
AMI_STATUS=$(aws ec2 describe-images --filter Name=tag-key,Values=Name Name=tag-value,Values=$BUILD-$DATE --query 'Images[*].{ID:State}' --output text)
while [  $AMI_STATUS != "available" ]; do
  AMI_STATUS=$(aws ec2 describe-images --filter Name=tag-key,Values=Name Name=tag-value,Values=$BUILD-$DATE --query 'Images[*].{ID:State}' --output text)
done

# Deploy with Ansible
ansible-playbook "./scripts/playbook.yml"

if [ "$?" -ne "0" ]; then
  echo "Ansible playbook failed."
  exit 1
fi

# Remove files
rm $KEY
