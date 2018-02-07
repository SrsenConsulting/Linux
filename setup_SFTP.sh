#!/bin/bash
# Setup SFTP server on Ubuntu Linux
# requires azure-cli

# Provide your own unique Key Vault name
keyvault_name=SCkeyvault
resource_group=SrsenConsulting

# Register the Key Vault provider
az provider register -n Microsoft.KeyVault

# Create a Key Vault for storing keys and enabled for disk encryption.
az keyvault create --name $keyvault_name --resource-group $resource_group --location westus \
    --enabled-for-disk-encryption True

# Create a key within the Key Vault.
az keyvault key create --vault-name $keyvault_name --name myKey --protection software

# Create an Azure Active Directory service principal for authenticating requests to Key Vault.
# Read in the service principal ID and password for use in later commands.
read sp_id sp_password <<< $(az ad sp create-for-rbac --query [appId,password] -o tsv)

# Grant permissions on the Key Vault to the AAD service principal.
az keyvault set-policy --name $keyvault_name --spn $sp_id \
    --key-permissions all \
    --secret-permissions all

# Create a virtual machine.
az vm create \
    --resource-group $resource_group \
    --name myVM \
    --image OpenLogic:CentOS:7.2n:7.2.20160629 \
    --admin-username azureuser \
    --generate-ssh-keys

# Encrypt the VM disks.
az vm encryption enable --resource-group $resource_group --name myVM \
  --aad-client-id $sp_id \
  --aad-client-secret $sp_password \
  --disk-encryption-keyvault $keyvault_name \
  --key-encryption-key myKey \
  --volume-type all

# Output how to monitor the encryption status and next steps.
echo "The encryption process can take some time. View status with:

    az vm encryption show --resource-group myResourceGroup --name myVM --query [osDisk] -o tsv

When encryption status shows \`VMRestartPending\`, restart the VM with:

    az vm restart --resource-group myResourceGroup --name myVM"



##########

sudo apt-get install openssh-server ecryptfs-utils cryptsetup
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.factory-defaults
sudo chmod a-w /etc/ssh/sshd_config.factory-defaults
sudo chown craig /etc/ssh/sshd_config
sudo addgroup ftpaccess


echo "Subsystem sftp internal-sftp" >> /etc/ssh/sshd_config
echo "Match group ftpaccess" >> /etc/ssh/sshd_config
echo "ChrootDirectory %h" >> /etc/ssh/sshd_config
echo "X11Forwarding no" >> /etc/ssh/sshd_config
echo "AllowTcpForwarding no" >> /etc/ssh/sshd_config
echo "ForceCommand internal-sftp" >> /etc/ssh/sshd_config

sudo service ssh restart

# Add SFTP user accounts
for i in {1..1}
do
  sudo adduser --encrypt-home ftpuser$i --ingroup ftpaccess --shell /usr/sbin/nologin
  sudo passwd ftpuser$i
  sudo chown root /home/ftpuser$i
  sudo mkdir /home/ftpuser$i/www

  sudo chown ftpuser$i:ftpaccess /home/ftpuser$i/www
  sudo chmod 711 /home/ftpuser$i
done

# Encryt swap partition
sudo ecryptfs-setup-swap

# delete a user
# userdel ftpuser1
