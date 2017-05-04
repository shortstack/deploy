# deploy

## deploy-vpc.sh

#### In order to deploy locally, you must do the following:

Install dependencies:

```bash
brew install postgresql
sudo pip install --upgrade pip
sudo pip install boto3 passlib
sudo pip install jinja2 --upgrade
sudo pip install ansible --upgrade
```

Configure AWS CLI tools:

```bash
aws configure
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

OpenVPN playbook runs, which installs and configures OpenVPN, sets the password for the openvpn administrator user, and allows access to the subnets that were generated within the VPC.

### Usage

Script requires 2 parameters:
* Environment - test, pre, prod
* CIDR - 18, 19, 20, etc. Ex: If you want a 172.19 VPC, enter 19. See deployment dashboard to see which ones are in use.

```bash
cd deploy
./scripts/deploy-vpc.sh -e dev -c 19
```

## deploy.sh

#### In order to deploy locally, you must do the following:

Configure AWS CLI tools:

```bash
sudo pip install awscli
```

---

This script uses Packer to create an AMI based on Amazon Linux with Docker. A new instance spins up and pulls the latest Docker image from the ECS repository. The instance is then shut down, and the new AMI is created.

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
* Location - local, circleci
* Tag - GitHub commit tag

```bash
cd deploy
./scripts/deploy.sh -e dev -b web -l local -t b5ee94d6dce18602691c961e5d0bad0d18ac73d5
```
