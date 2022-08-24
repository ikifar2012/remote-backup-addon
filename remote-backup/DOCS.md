# Documentation

Please visit the documentation at [addons.mathesonsteplock.ca](https://addons.mathesonsteplock.ca/docs/addons/remote-backup/basic-config)

## Security
For SSH and rsync operation it is recommend to add the public key of the remote host to the file `/ssl/known_hosts`. If you see a warning `Missing known_hosts file!` then you have not done so and the add-on automatically does it for you each time it is called.
**Note that this is a security risk** which can be fixed by executing `ssh-keyscan -t rsa <remote host> >> /ssl/known_hosts` from a terminal, e.g. [SSH & Web Terminal](https://github.com/hassio-addons/addon-ssh).

# Support Me

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/mathesonsteplock)
