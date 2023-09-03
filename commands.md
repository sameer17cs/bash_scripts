## Add ssh key in linux
 - `chmod 400 ~/.ssh/{your_privatekey}`
 - ``eval `ssh-agent -s`; ssh-add ~/.ssh/{your_privatekey}``

## Resize Filesystem
 - `sudo growpart /dev/sda 1` 
 - `sudo resize2fs /dev/sda`

