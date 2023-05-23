# cloudera migration environment setup

Date Created: May 19, 2023 9:09 AM
tags: ansible, azure, cloudera, migrations, terraform

# Open Source Kafka to Confluent Platform Migrations Scenarios

Apache Kafka to CP Migration scenarios runbook

## Azure setup

1. Log into azure 
    
    ```bash
    az login
    ```
    
2. Create resource group and app registration
    
    ```bash
    az group create --name cloudera-migration --location westeurope \
    --tags 'owner_email=ogomezsoriano@confluent.io'
    
    az ad app create --display-name cloudera-migration-app-registration
    ```
    
3. Find the account id (for example for a single account present)
    
    ```bash
    export ACCOUNT_ID=$(az account list | jq -r '.[0].id')
    echo $ACCOUNT_ID
    54ff81a0-e7f6-4919-9053-4cdd1c5f5ae1
    ```
    
4. Set subscription to match the account id
    
    ```bash
    az account set --subscription "$ACCOUNT_ID"
    ```
    
5. Create an identity 
    
    ```bash
    az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/$ACCOUNT_ID"
    Creating 'Contributor' role assignment under scope '/subscriptions/54ff81a0-e7f6-4919-9053-4cdd1c5f5ae1'
    The output includes credentials that you must protect. Be sure that you do not include these credentials in your code or check the credentials into your source control. For more information, see https://aka.ms/azadsp-cli
    {
      "appId": "*** application id ***",
      "displayName": "azure-cli-display-name",
      "password": "*** password ***",
      "tenant": "*** tenant ***"
    }
    ```
    
6. Set environment 
    ```bash
    export ARM_CLIENT_ID="*** application id ***"
    export ARM_CLIENT_SECRET="*** password ***"
    export ARM_SUBSCRIPTION_ID="$ACCOUNT_ID"
    export ARM_TENANT_ID="*** tenant ***"
    ```
    
7. Create ssh key 
    
    ```bash
    az sshkey create --name "migrations-SSHKey" --resource-group "migrations"
    
    No public key is provided. A key pair is being generated for you.
    Private key is saved to "/Users/vcosqui/.ssh/migrations-SSHKey".
    Public key is saved to "/Users/vcosqui/.ssh/migrations-SSHKey.pub".
    ```
    
8. Create a network 
    
    ```bash
    az network vnet create \
      --name migrations-vnet \
      --resource-group migrations \
      --address-prefix 10.1.0.0/16
    ```
    

## Source cluster deployment

1. Setup environment
    
    ```bash
    export TF_VAR_pub_key_path="~/.ssh/migrations-SSHKey.pub"
    export TF_VAR_resource_group_name="migrations"
    export TF_VAR_vnet_name="migrations-vnet"
    export TF_VAR_subnet_name="migrations-source-subnet"
    export TF_VAR_subnet_addres_prefix="10.1.0.0/24"
    export TF_VAR_user_name="kafka"
    
    export TF_VAR_zk_vm_type="Standard_B2ms"
    export TF_VAR_zk_data_disk_size=40
    export TF_VAR_zk_data_disk_count=1
    export TF_VAR_zk_log_disk_size=80
    export TF_VAR_broker_vm_type="Standard_B2ms"
    export TF_VAR_broker_log_disk_size=80
    export TF_VAR_broker_log_disk_count=1
    export TF_VAR_sr_count=1
    export TF_VAR_connect_count=1
    export TF_VAR_ksql_count=1
    export TF_VAR_c3_count=1
    ```
    
2. Prepare and run deployment
    
    ```bash
    # clone terraform project
    git clone git@github.com:ogomezso/tf-cp-cloud-infra-provision.git
    cd tf-cp-cloud-infra-provision/azure

    # init
    terraform init -backend-config "resource_group_name=migrations" \
     -backend-config "storage_account_name=migrationstfstateazure" \
     -backend-config "container_name=tfstate" \
     -backend-config "key=terraform.tfstate"

    # plan
    terraform plan -out main.tfplan

    # apply
    terraform apply "main.tfplan"
    ```
    
3. OS Source Kafka deployment (todo: migrate to cp-ansible)
    
    ```bash
    # Install Azure.Azcollection inventory plugin
    ansible-galaxy collection install azure.azcollection:1.11.0 && \
    pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements-azure.txt
    
    # declare private key location
    export ANSIBLE_KEY_FILE="~/.ssh/migrations-SSHKey"
    
    # clone 
    git clone git@github.com:vcosqui/ansible-os-kafka-deployment.git
    cd ansible-os-kafka-deployment
    
    # setup inventory hosts file
    [all:vars]
    zookeeper_servers_use_inventory_hostname = true
    
    [kafka_nodes:vars]
    kafka_zookeeper_connect=zookeeper1:2181,zookeeper2:2181,zookeeper3:2181
    kafka_auto_create_topics_enable=true
    
    [kafka_nodes]
    kafka1 kafka_broker_id=1 ansible_host=10.1.0.7
    kafka2 kafka_broker_id=2 ansible_host=10.1.0.5
    kafka3 kafka_broker_id=3 ansible_host=10.1.0.6
    
    [zookeeper_nodes]
    zookeeper1 zookeeper_id=1 ansible_host=10.1.0.9
    zookeeper2 zookeeper_id=2 ansible_host=10.1.0.8
    zookeeper3 zookeeper_id=3 ansible_host=10.1.0.4
    
    # test you host reachability
    ansible all -m ping -i hosts
    
    # install zookeeper and OS kafka
    ansible-galaxy install sleighzy.zookeeper
    ansible-playbook zookeeper.yaml -i hosts
    ansible-galaxy install sleighzy.kafka
    ansible-playbook kafka.yaml -i hosts
    
    # test producer
    echo "test message" |  kafkacat -b kafka1 -t test -P
    # test consumer
    kafkacat -b kafka1 -t test
    ```
    

## Destination cluster deployment

1. Setup environment
    
    ```bash
    export TF_VAR_pub_key_path="~/.ssh/migrations-SSHKey.pub"
    export TF_VAR_resource_group_name="migrations"
    export TF_VAR_vnet_name="migrations-vnet"
    export TF_VAR_subnet_name="migrations-destination-subnet"
    export TF_VAR_subnet_addres_prefix="10.1.1.0/24"
    export TF_VAR_user_name="kafka"
    
    export TF_VAR_zk_vm_type="Standard_B2ms"
    export TF_VAR_zk_data_disk_size=40
    export TF_VAR_zk_data_disk_count=1
    export TF_VAR_zk_log_disk_size=80
    export TF_VAR_broker_vm_type="Standard_B2ms"
    export TF_VAR_broker_log_disk_size=80
    export TF_VAR_broker_log_disk_count=1
    export TF_VAR_sr_count=1
    export TF_VAR_connect_count=1
    export TF_VAR_ksql_count=1
    export TF_VAR_c3_count=1
    ```
    
2. Prepare and run deployment
    
    ```bash
    # clone terraform project
    git clone git@github.com:ogomezso/tf-cp-cloud-infra-provision.git
    cd tf-cp-cloud-infra-provision/azure

    # init
    terraform init -backend-config "resource_group_name=migrations" \
     -backend-config "storage_account_name=migrationstfstateazure" \
     -backend-config "container_name=tfstatedestination" \
     -backend-config "key=terraform.tfstate"

    # plan
    terraform plan -out main.tfplan

    # apply
    terraform apply "main.tfplan"
    ```
    
3. Confluent Platform deployment
    
    ```bash
    # log into your jumphost with ssh access to the VMs
    ssh azureuser@20.224.156.254 -i ~/.ssh/migrations-SSHKey
    
    # clone github repo
    git clone git@github.com:vcosqui/ansible-cp-deployment.git 
    cd ansible-cp-deployment
    
    # install confluent platform via ansible-galaxy
    ansible-galaxy collection install confluent.platform
    
    # test you host reachability
    ansible -i hosts.yml all -m ping
    
    # validate hosts
    ansible-playbook -i hosts.yml confluent.platform.validate_hosts
    
    # install confluent platform
    ansible-playbook -i hosts.yml confluent.platform.all
    
    ```
