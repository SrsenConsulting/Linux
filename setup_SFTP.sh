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
    --image OpenLogic:CentOS:7.2n:7.2.20160629 \
    --admin-username azureuser \
    --generate-ssh-keys

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

    az vm restart --resource-group myResourceGroup --name myVM"


write_files:
-   encoding: b64
    content: |
    # revised sshd_config
    # See the sshd_config(5) manpage for details

    # What ports, IPs and protocols we listen for
    Port 22
    # Use these options to restrict which interfaces/protocols sshd will bind to
    #ListenAddress ::
    #ListenAddress 0.0.0.0
    Protocol 2
    # HostKeys for protocol version 2
    HostKey /etc/ssh/ssh_host_rsa_key
    HostKey /etc/ssh/ssh_host_dsa_key
    HostKey /etc/ssh/ssh_host_ecdsa_key
    HostKey /etc/ssh/ssh_host_ed25519_key
    #Privilege Separation is turned on for security
    UsePrivilegeSeparation yes

    # Lifetime and size of ephemeral version 1 server key
    KeyRegenerationInterval 3600
    ServerKeyBits 1024

    # Logging
    SyslogFacility AUTH
    LogLevel VERBOSE

    # Authentication:
    LoginGraceTime 120
    PermitRootLogin prohibit-password
    StrictModes yes

    RSAAuthentication yes
    PubkeyAuthentication yes
    #AuthorizedKeysFile	%h/.ssh/authorized_keys

    # Don't read the user's ~/.rhosts and ~/.shosts files
    IgnoreRhosts yes
    # For this to work you will also need host keys in /etc/ssh_known_hosts
    RhostsRSAAuthentication no
    # similar for protocol version 2
    HostbasedAuthentication no
    # Uncomment if you don't trust ~/.ssh/known_hosts for RhostsRSAAuthentication
    #IgnoreUserKnownHosts yes

    # To enable empty passwords, change to yes (NOT RECOMMENDED)
    PermitEmptyPasswords no

    # Change to yes to enable challenge-response passwords (beware issues with
    # some PAM modules and threads)
    ChallengeResponseAuthentication no

    # Change to no to disable tunnelled clear text passwords
    #PasswordAuthentication yes

    # Kerberos options
    #KerberosAuthentication no
    #KerberosGetAFSToken no
    #KerberosOrLocalPasswd yes
    #KerberosTicketCleanup yes

    # GSSAPI options
    #GSSAPIAuthentication no
    #GSSAPICleanupCredentials yes

    X11Forwarding no
    X11DisplayOffset 10
    PrintMotd no
    PrintLastLog yes
    TCPKeepAlive yes
    #UseLogin no

    #MaxStartups 2:30:10
    #Banner /etc/issue.net

    # Allow client to pass locale environment variables
    AcceptEnv LANG LC_*

    Subsystem sftp internal-sftp

    # Set this to 'yes' to enable PAM authentication, account processing,
    # and session processing. If this is enabled, PAM authentication will
    # be allowed through the ChallengeResponseAuthentication and
    # PasswordAuthentication.  Depending on your PAM configuration,
    # PAM authentication via ChallengeResponseAuthentication may bypass
    # the setting of "PermitRootLogin without-password".
    # If you just want the PAM account and session checks to run without
    # PAM authentication, then enable this but set PasswordAuthentication
    # and ChallengeResponseAuthentication to 'no'.
    UsePAM yes

    # Srsen Consulting mods
    Match group ftpaccess
    ChrootDirectory %h
    AllowTcpForwarding no
    ForceCommand internal-sftp
    path: /etc/ssh
    owner: root:root
    permissions: '0711'


#########
sudo apt-get install openssh-server
sudo chown craig /etc/ssh/sshd_config
sudo addgroup ftpaccess
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
