# deploy

## deploy-vpc.sh

#### In order to deploy locally, you must do the following:

Install dependencies:

```bash
sudo pip install --upgrade pip
sudo pip install boto3 passlib
sudo pip install jinja2 --upgrade
sudo pip install ansible --upgrade
```

Configure AWS CLI tools:

```bash
sudo pip install awscli
```
---

This script uses Ansible to deploy an AWS CloudFormation template. It builds a CloudFormation stack, which creates the following:

* VPC
* Private subnets - 2x web, 2x API, 2x database
* Public subnets - 2x web load balancer, 2x API load balancer, 1x VPN, 1x NAT
* Private RDS subnet group
* Private route
* Public route
* Private route table and network ACL
* Public route table and network ACL
* NAT gateway
* Internet gateway
* Security groups - Web servers and load balancer, API servers and load balancer, database, OpenVPN, bastion
* EIP - NAT gateway
* EIP - OpenVPN instance
* EC2 instance - OpenVPN
* EC2 instance - Bastion

These are all tagged appropriately such that the API/web deploy script will pick up the tags associated with the newly created VPC components, and we will be able to automatically create a new environment and deploy the web and API builds to it.

OpenVPN playbook runs, which installs and configures OpenVPN with 2 factor authentication enabled, sets the password for the openvpn administrator user, and allows access to the subnets that were generated within the VPC. You will need to SSH in and set up an admin user when this is complete.

### Usage

Modify env-dev-deploy.template file with your own information.

Script requires 2 parameters:
* Environment - dev, test, prod
* CIDR - 18, 19, 20, etc. Ex: If you want a 172.19 VPC, enter 19.

```bash
cd deploy
cp env/env-dev-deploy.template env/env-dev-deploy.list
./scripts/deploy-vpc.sh -e dev -c 19
```

#### When the OpenVPN playbook completes, do the following to add an admin user to OpenVPN:

```bash
ssh -i key.pem ec2-user@{ openvpn-ip }
sudo -i
useradd { username }
passwd { username }
/usr/local/openvpn_as/scripts/sacli --user { username } --key prop_superuser --value true UserPropPut
su - { username }
google-authenticator
```

You can now log into the VPN at https://{ openvpn-ip }:943

You will now also want to lock down the OpenVPN security group to allow SSH from only your location, instead of 0.0.0.0/0.

## deploy.sh

#### In order to deploy locally, you must do the following:

Configure AWS CLI tools:

```bash
sudo pip install awscli
```

Modify Dockerfile and build Docker images or add your own. Then push to ECS repositories.
```
eval sudo $(aws ecr get-login --region us-east-1)

cd build/api
docker build -t api .
docker tag api:latest { aws_account }.dkr.ecr.us-east-1.amazonaws.com/api:latest
docker push { aws_account }.dkr.ecr.us-east-1.amazonaws.com/api:latest

cd ../web
docker build -t web .
docker tag web:latest { aws_account }.dkr.ecr.us-east-1.amazonaws.com/web:latest
docker push { aws_account }.dkr.ecr.us-east-1.amazonaws.com/web:latest
```

---

This script uses Packer to create an AMI based on Amazon Linux with Docker. A new instance spins up and pulls the latest Docker image from your ECS repository. The instance is then shut down, and the new AMI is created.

Once the AMI has been created, an Ansible playbook runs.
* Finds the proper VPC, subnet, security group, and auto scaling group
* Generates a user-data script
 * Gets correct Docker image ID
 * Creates the correct Docker run command with image ID and environment variables
* Creates a new launch configuration with the AMI and user-data script
* Updates (or creates) the auto scaling group to use the launch configuration
* Updates (or creates) the load balancer
* Adds the appropriate amount of new instances to the load balancer via the auto scaling group
* Shuts down old instances once new instances are healthy

### Usage

Script requires 4 parameters:
* Environment - dev, test, prod
* Build - web, api
* Location - linux, mac
* Tag - GitHub commit tag

```bash
cd deploy
./scripts/deploy.sh -e dev -b web -l mac -t b5ee94d6dce18602691c961e5d0bad0d18ac73d5
```
