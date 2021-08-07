# Load Configuration

1. Enter configuration mode.

```
configure
```

2. Load the backup configuration from a local or a remote file.

```
load ?

Possible completions:
  <Enter>                               Load from system config file
  <file>                                Load from file on local machine
  scp://<user>:<passwd>@<host>/<file>   Load from file on remote machine
  sftp://<user>:<passwd>@<host>/<file>  Load from file on remote machine
  ftp://<user>:<passwd>@<host>/<file>   Load from file on remote machine
  http://<host>/<file>                  Load from file on remote machine
  tftp://<host>/<file>                  Load from file on remote machine

load tftp://192.168.1.10/config.boot
######################################################################## 100.0%
Loading configuration from '/config/config.boot.2380'...

Load complete. Use 'commit' to make changes active.
```

3. Compare the differences between the backup/working configuration and the active configuration.

```
compare
```

4. Commit the changes and save the active configuration to the startup/boot configuration.

```
commit ; save
```