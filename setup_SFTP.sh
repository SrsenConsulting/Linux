#!/bin/bash
# Setup SFTP server on Ubuntu Linux
# requires azure-cli

az login

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
    --name SFTPserver \
    --image UbuntuLTS \
    --admin-username azureuser \
    --generate-ssh-keys \
    --custom-data cloud-init.txt

# Encrypt the VM disks.
az vm encryption enable --resource-group $resource_group --name SFTPserver \
  --aad-client-id $sp_id \
  --aad-client-secret $sp_password \
  --disk-encryption-keyvault $keyvault_name \
  --key-encryption-key myKey \
  --volume-type all

# Output how to monitor the encryption status and next steps.
echo "The encryption process can take some time. View status with:

    az vm encryption show --resource-group myResourceGroup --name myVM --query [osDisk] -o tsv

When encryption status shows \`VMRestartPending\`, restart the VM with:

    az vm restart --resource-group $resource_group --name SFTPserver"
